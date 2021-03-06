{-# LANGUAGE OverloadedStrings #-}
module Main where

import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import Data.List (intercalate)
import Data.List.Split
import Data.Maybe
import Data.String
import qualified Regex.RE2 as RE
import System.Environment
import System.FilePath
import System.IO
import System.Console.GetOpt
import System.Exit

import Indent

-- Converting whole input to JSON

escape :: Char -> String
escape c = case c of
    '"' -> "\\\""
    '\\' -> "\\\\"
    '\b' -> "\\b"
    '\f' -> "\\f"
    '\n' -> "\\n"
    '\r' -> "\\r"
    '\t' -> "\\t"
    c' -> [c']

dumpJson :: Value -> String
dumpJson (Scalar s) = "\""++(concat $ map escape s)++"\""
dumpJson (Sequence vs) = "["++(intercalate "," $ map dumpJson vs)++"]"

yamelotToJson :: IO ()
yamelotToJson = do
      input <- getContents
      case run input yamelot of
          Just (v, s) -> putStrLn $ dumpJson v
          Nothing -> do
              putStrLn "error!"
              exitFailure

-- Running a sequence of tests

runTestCase :: BC.ByteString -> IO ()
runTestCase caseBytes =
    case RE.find pattern case_ of
      Nothing -> die ("parse error in test case: " ++ show case_)
      Just m -> if expected == actual
                then putStrLn "pass"
                else if attrXfail
                     then putStrLn "xfail"
                     else printFailure document expected actual
        where attrs = BC.split ' ' (fromMaybe "" (RE.matchGroup m 1))
              input = fromMaybe "" (RE.matchGroup m 2)
              expected = RE.matchGroup m 3
              attrChomped = elem "chomped" attrs
              attrXfail = elem "Xhaskell" attrs
              document = if attrChomped
                         then input
                         else BC.append input "\n"
              actual = case run (BC.unpack document) yamelot of
                Just (v, []) -> Just (BC.pack (dumpJson v))
                Just (v, _) -> Nothing
                Nothing -> Nothing
  where (case_, _) = RE.replaceAll "(?m)^###.*\n?" caseBytes ""
        pattern :: RE.Pattern
        pattern = fromString ("(?s)\\A" ++
            "(?:ATTR ([^\n]*)\n)?" ++
            "(.*)\n" ++
            "(?:" ++
                "!!!!!!!!!!\n" ++ "|" ++
                "(?:----------\n(.*)\n)" ++
            ")\\z")
        printFailure document expected actual = do
          putStrLn "fail!"
          putStrLn ("  On input " ++ show document)
          putStrLn ("  expected " ++ render expected)
          putStrLn ("  but got " ++ render actual)
          where render res = BC.unpack (fromMaybe "error" res)

runTestFile :: FilePath -> IO ()
runTestFile path = do
      input <- BC.readFile path
      let cases = splitCases input
      putStrLn ("file " ++ path ++ ": " ++ show (length cases) ++ " cases")
      mapM_ runTestCase cases
  where splitCases text = hd : if BC.null tl then []
                               else splitCases (BC.drop (BC.length sep) tl)
          where (hd, tl) = BC.breakSubstring sep text
                sep = BC.append (BC.replicate 40 '=') ("\n")

runTests :: [FilePath] -> IO ()
runTests positionals = do
      mapM_ runTestFile positionals

-- The command line

data Options = Options { optTest :: Bool }

startOptions :: Options
startOptions = Options { optTest = False }

options :: [OptDescr (Options -> IO Options)]
options = [
    Option "t" ["test"]
      (NoArg (\opt -> return opt { optTest = True }))
      "Take input files as sets of test cases"
  , Option "" ["help"]
      (NoArg (\_ -> do name <- getProgName
                       hPutStrLn stderr (usageInfo name options)
                       exitSuccess))
      "Show a usage message"
  ]

main :: IO ()
main = do
    args <- getArgs
    let (actions, positionals, errors) = getOpt RequireOrder options args
    opts <- foldl (>>=) (return startOptions) actions
    if optTest opts then
      runTests positionals
    else
      yamelotToJson
