{-# LANGUAGE ScopedTypeVariables, DeriveDataTypeable #-}

-- | For an example, see
-- <https://ro-che.info/articles/2015-01-02-lexical-analysis>
module Language.Lexer.Applicative (tokens, tokensEither, LexicalError(..)) where

import Control.Exception
import Data.Loc
import Data.List
import Data.Maybe
import Data.Typeable (Typeable)
import System.IO.Unsafe (unsafePerformIO)
import Text.Regex.Applicative

annotate
  :: String -- ^ source file name
  -> String -- ^ contents
  -> [(Char, Pos, Pos)] -- ^ the character, its position, and the previous position
annotate src s = snd $ mapAccumL f (startPos src, startPos src) s
  where
    f (pos, prev_pos) ch =
      let pos' = advancePos pos ch
      in pos' `seq` ((pos', pos), (ch, pos, prev_pos))

-- | The lexical error exception
data LexicalError = LexicalError !Pos
  deriving (Eq, Typeable)

instance Show LexicalError where
  show (LexicalError pos) = "Lexical error at " ++ displayPos pos

instance Exception LexicalError

-- | The lexer.
--
-- In case of a lexical error, throws the 'LexicalError' exception.
-- This may seem impure compared to using 'Either', but it allows to
-- consume the token list lazily.
--
-- Both token and whitespace regexes consume as many characters as possible
-- (the maximal munch rule). When a regex returns without consuming any
-- characters, a lexical error is signaled.
tokens
  :: forall token.
     RE Char token -- ^ regular expression for tokens
  -> RE Char ()    -- ^ regular expression for whitespace and comments
  -> String        -- ^ source file name (used in locations)
  -> String        -- ^ source text
  -> [L token]
tokens pToken pJunk src = go . annotate src
  where
  go :: [(Char, Pos, Pos)] -> [L token]
  go l = case l of
    [] -> []
    s@((_, pos1, _):_) ->
      case findLongestPrefix re s of
        -- If the longest match is empty, we have a lexical error
        Just (v, (_, pos1', _):_) | pos1' == pos1 ->
          throw $ LexicalError pos1

        Just (Just tok, rest) ->
          let
            pos2 =
              case rest of
                (_, _, p):_ -> p
                [] -> case last s of (_, p, _) -> p

          in L (Loc pos1 pos2) tok : go rest

        Just (Nothing, rest) -> go rest

        Nothing -> throw $ LexicalError pos1

  re :: RE (Char, Pos, Pos) (Maybe token)
  re = comap (\(c, _, _) -> c) $ (Just <$> pToken) <|> (Nothing <$ pJunk)

-- | Like `tokens`, but pure, and strict in the spine of the list.
tokensEither
  :: forall token.
     RE Char token -- ^ regular expression for tokens
  -> RE Char ()    -- ^ regular expression for whitespace and comments
  -> String        -- ^ source file name (used in locations)
  -> String        -- ^ source text
  -> Either LexicalError [L token]
tokensEither pToken pJunk src =
  unsafePerformIO
  . try
  . evaluate
  . forceSpine
  . tokens pToken pJunk src
  where
    forceSpine :: [a] -> [a]
    forceSpine xs = foldr (const id) () xs `seq` xs

    lmap :: (a -> b) -> Either a c -> Either b c
    lmap f (Left a)  = Left (f a)
    lmap _ (Right b) = Right b
