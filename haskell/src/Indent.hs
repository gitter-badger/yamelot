module Indent where

import Data.Char
import qualified Debug.Trace
import Control.Applicative
import Control.Monad

--trace = Debug.Trace.trace
trace _ = id

-- | Since this is a scanner-less parser, our tokens are just
-- characters.
type Token = Char

-- | An inclusive range between two integers.
type Range = (Int, Int) -- inclusive

-- | Tests if @i@ in 'Range'.
inRange :: Int -> Range -> Bool
inRange i (j, k) = i >= j && i <= k

-- | Hack to represent an infinite integer (so this will break if
-- we have any columns greater than this volume).  Proper way to
-- do this is have a proper data type for integers plus infinity.
inf :: Int
inf = 99999999

newtype Parse a =
    Parse {
        runParse :: [(Token, Int)]
                 -> Range
                 -> Maybe (a, [(Token, Int)], Range) }

instance Monad Parse where
    return x = Parse $ \cs i -> Just (x, cs, i)
    m >>= f = Parse $ \cs i ->
        -- TODO: better to factor this out so we can do both loose and
        -- lock
        case runParse m cs i of
            Nothing -> Nothing
            Just (a, cs', i') -> case runParse (f a) cs' (lockRightConstraint Loose i i') of
                Nothing -> Nothing
                Just (b, cs'', i'') -> Just (b, cs'', lockWholeResult Loose i' i'')

instance Applicative Parse where
    pure = return
    (<*>) = ap

instance Alternative Parse where
    empty = Parse $ \_ _ -> Nothing
    p1 <|> p2 = choice p1 p2

instance Functor Parse where
  fmap ff p = Parse $ \cs i -> fmap (\(a, cs', i') -> (ff a, cs', i')) (runParse p cs i)
data Value = Scalar String
           | Sequence [Value]
  deriving (Show)

failParse :: Parse a
failParse = Parse $ \cs i -> Nothing

epsilon :: Parse ()
epsilon = Parse $ \cs i -> Just ((), cs, i)

termSatisfy :: (Char -> Bool) -> Parse Char
termSatisfy pred = Parse go
    where go [] _ = Nothing
          go ((c,k):cs) i
            | pred c && k `inRange` i = Just (c, cs, (k, k))
            | otherwise               = Nothing

term :: Char -> Parse Char
term c = termSatisfy (==c)

munge = map fst

{-
  Lock: the whole, the left, and the right all have the same indentation
  Loose: the whole and left have the same indentation,
         and the right is unconstrained
  Band: the whole and left have the same indentation, and the right has
        the same constraint as the whole and left
-}
data Lock = Lock | Loose | Band

lockRightConstraint :: Lock -> Range -> Range -> Range
lockRightConstraint Lock  _               leftResult = leftResult
lockRightConstraint Loose _               _          = (0, inf)
lockRightConstraint Band  wholeConstraint _          = wholeConstraint

lockWholeResult :: Lock -> Range -> Range -> Range
lockWholeResult Lock  _          rightResult = rightResult
lockWholeResult Loose leftResult _           = leftResult
lockWholeResult Band  leftResult _           = leftResult

sqAny :: Lock -> Parse a -> Parse b -> Parse (a,b)
sqAny l p1 p2 = Parse $ \cs i ->
    case runParse p1 cs i of
        Nothing -> Nothing
        Just (a, cs', i') -> case runParse p2 cs' (lockRightConstraint l i i') of
            Nothing -> Nothing
            Just (b, cs'', i'') -> Just ((a,b), cs'', lockWholeResult l i' i'')

sq = sqAny Loose
sqLock = sqAny Lock

sql :: Parse a -> Parse b -> Parse a
sql p1 p2 = fmap fst (p1 `sq` p2)

sqr :: Parse a -> Parse b -> Parse b
sqr p1 p2 = fmap snd (p1 `sq` p2)

between :: Parse a -> Parse c -> Parse b -> Parse b
between pl pr p = pl `sqr` p `sql` pr

choice :: Parse a -> Parse a -> Parse a
choice p1 p2 = Parse $ \cs i ->
    case runParse p1 cs i of
        Nothing -> case runParse p2 cs i of
            Nothing -> Nothing
            Just (a, cs', i') -> Just (a, cs', i')
        Just (a, cs', i') -> Just (a, cs', i')

option :: Parse a -> Parse (Maybe a)
option p = Parse $ \cs i ->
    case runParse p cs i of
        Nothing -> Just (Nothing, cs, i)
        Just (a, cs', i') -> Just (Just a, cs', i')

starAny :: Lock -> Parse a -> Parse [a]
starAny l p = Parse $ \cs i ->
    case runParse p cs i of
        Nothing -> Just ([], cs, i)
        Just (a, cs', i') ->
            case runParse (starAny l p) cs' (lockRightConstraint l i i') of
                Nothing -> Nothing
                Just (as, cs'', i'') -> Just (a:as, cs'', lockWholeResult l i' i'')

star = starAny Loose
starLock = starAny Lock

timesAny :: Lock -> (Int, Int) -> Parse a -> Parse [a]
timesAny l (lo,hi) p = case (lo, hi) of
    (0, 0) -> fmap (const []) epsilon
    (0, hi) -> more (timesAny l (0,hi-1) p) `choice` fmap (const []) epsilon
    (lo, hi) -> more (timesAny l (lo-1,hi-1) p)
  where more pp = fmap (uncurry (:)) $ sqAny l p $ pp

times = timesAny Loose

data Indent = IGt | IGte | IAll

indent :: Indent -> Parse a -> Parse a
indent ind p = Parse $ \cs i ->
    case runParse p cs (fwd ind i) of
        Nothing -> Nothing
        Just (a, cs', i') -> Just (a, cs', i `intersect` bwd ind i')

maxInd :: Parse a -> Parse a
maxInd p = Parse $ \cs i ->
    case runParse p cs i of
        Nothing -> Nothing
        Just (a, cs', (_,ir)) | ir == inf -> Nothing
                              | otherwise -> Just (a, cs', (ir,ir))

intersect (l,h) (l',h') = (max l l', min h h')

plus p = Parse $ \cs i -> case runParse (p `sq` star p) cs i of
    Nothing -> Nothing
    Just ((t,ts), cs', i') -> Just (t:ts, cs', i')

plusLock p = Parse $ \cs i -> case runParse (p `sqLock` starLock p) cs i of
    Nothing -> Nothing
    Just ((t,ts), cs', i') -> Just (t:ts, cs', i')

sepEndBy :: Parse a -> Parse b -> Parse [b]
sepEndBy sep elt =
    fmap coalesce $ option $
        elt `sq` star (sep `sqr` elt) `sql` option sep
  where coalesce Nothing = []
        coalesce (Just (v,vs)) = v:vs

gt = indent IGt
gte = indent IGte
iall = indent IAll

fwd IGt (l,h) = (l+1,inf)
fwd IGte (l,h) = (l,inf)
fwd IAll (l,h) = (0,inf)

bwd IGt (l,h) = (0,h-1)
bwd IGte (l,h) = (0,h)
bwd IAll (l,h) = (0,inf)

startIx = 0
ann :: String -> [(Char, Int)]
ann xs = go startIx xs
    where go _ [] = []
          go i ('\n':xs) = ('\n', i) : go startIx xs
          go i (' ':xs) = (' ', i) : go (i+1) xs
          go i (x:xs) = (x, i) : go (i+1) xs

run :: String -> Parse a -> Maybe (a, String)
run cs p = fmap (\(t,xs,_) -> (t,munge xs)) (runParse p (ann cs) (0, inf))

{-
Possible next hard parts:
* literal scalars, with explicit indentation
* more-complete plain scalars
* Handle lack of trailing newline again, more cleanly than ``option (term '\n')``.
  Probably add an EOF sentinel, make something that's "newline or EOF".

Annoying parts, should fix:
* The convention where each top-level node is responsible for consuming
  the whitespace that follows it, right up through the indentation of the
  next thing, is kind of odd and probably confusing.

Easy(??) parts that will cover a bunch more tests:
* mappings
* numbers
-}

-- Fail if the parse results in an empty string.
nonEmpty :: Parse String -> Parse String
nonEmpty p  = Parse $ \cs i ->
    case runParse p cs i of
        Nothing -> Nothing
        Just ("", cs, i) -> Nothing
        Just value -> Just value

ws = star $ termSatisfy (flip elem " \n")
eat = (`sql` ws)
tok = eat . term
wsLines = star $ star (term ' ') `sq` term '\n'
eatLines = (`sql` wsLines)
tokLines = eatLines . term

useIndent :: (Range -> Parse a) -> Parse a
useIndent f = Parse $ \cs i -> runParse (f i) cs i

fullIndent :: Parse String
fullIndent = useIndent (\i -> times (fst i, fst i) (iall $ term ' '))

subIndent :: Parse String
subIndent = useIndent $ \i -> case fst i of
    0 -> failParse
    l -> times (0, l-1) (iall $ term ' ')

flow_scalar = fmap Scalar $ eat $ maxInd $ plus $ termSatisfy isAlphaNum
flow_list = fmap Sequence $ between (tok '[') (tok ']') $
    sepEndBy (tok ',') flow_node
flow_collection = flow_list
flow_node = flow_scalar `choice` flow_collection

traceParse msg p = Parse $ \cs i ->
  let header = msg ++ " " ++ show i ++ ": " in
  case runParse p cs i of
    Nothing -> trace (header ++ "fail") $ Nothing
    r@(Just (a, cs', i')) -> trace (header ++ show a ++ " (rest " ++ (show (munge cs')) ++ ")") $ r

literal_scalar = traceParse "literal" $ eat $ fmap join $
    (gte $ tok '|') `sqLock` gte (firstLine `sqLock` starLock restLine)
  where firstLine = traceParse "firstLine" $ lineContents
        restLine = (traceParse "short blank" $ fmap (:[]) $ subIndent `sqr` term '\n')
            `choice` (traceParse "indented line" $ fullIndent `sqr` lineContents)
        lineContents = fmap squash $
            star (termSatisfy (/='\n')) `sq` term '\n'
          where squash (l, nl) = l ++ [nl]
        join (_, (line, lines)) = Scalar $ concat (line:lines)
block_scalar = flow_scalar `choice` literal_scalar
block_list = fmap Sequence $ plusLock $ traceParse "list_item" item
  where item = fmap snd $ tok '-' `sqLock`
                 gt ( block_list
             `choice` block_scalar
             `choice` flow_collection
                    )

yamelot = ws `sqr` block_list
