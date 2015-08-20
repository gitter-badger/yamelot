module Lib
    ( parseYamelot
    , Value(..)
    ) where

import Text.ParserCombinators.Parsec

data Value = Scalar String | Seq [Value]
  deriving (Eq, Show)

flowSequence = between (char '[') (char ']') $
                 Seq <$> sepEndBy flowNode (char ',')

flowNode = Scalar <$> flowScalar

flowScalar = many1 $ alphaNum

parseYamelot :: String -> Either ParseError Value
parseYamelot input = parse flowSequence "(unknown)" input
