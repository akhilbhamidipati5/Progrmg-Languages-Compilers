{-# LANGUAGE FlexibleContexts #-}

module Scheme.Runtime where

import Scheme.Core
import Scheme.Parse
import Scheme.Eval

import qualified Data.HashMap.Strict as H
import Text.ParserCombinators.Parsec hiding (Parser, State)
import Control.Monad
import Control.Monad.State
import Control.Monad.Except
import Data.Foldable

--- ### Helper functions for lifting and lowering

lowerBool :: Val -> Bool
lowerBool (Boolean False) = False
lowerBool _ = True

lowerInt :: Val -> EvalState Int
lowerInt (Number i) = return i
lowerInt v = throwError $ TypeError v

lowerList :: Val -> EvalState [Val]
lowerList (List xx) = return xx
lowerList v = throwError $ TypeError v

liftIntVargOp :: (Int -> Int -> Int) -> Int -> Val
liftIntVargOp f c = PrimFunc p where
  p [] = return $ Number c
  p [x] = Number . f c <$> lowerInt x
  p xx = Number . foldl1 f <$> mapM lowerInt xx

liftBoolVargOp :: ([Bool] -> Bool) -> Val
liftBoolVargOp f = PrimFunc $ return . Boolean . f . map lowerBool

-- TODO
liftIntBinOp :: (Int -> Int -> Int) -> Val
liftIntBinOp f  = PrimFunc p where 
  p [] = throwError (UnexpectedArgs [])
  p [x] = throwError (UnexpectedArgs [x])
  p xx = Number . foldl1 f <$> mapM lowerInt xx

-- TODO
liftIntUnaryOp :: (Int -> Int) -> Val
liftIntUnaryOp f = PrimFunc p where
  p [] = throwError (UnexpectedArgs [])
  p [x] = Number . f <$> lowerInt x
  p v = throwError (UnexpectedArgs v)

liftBoolUnaryOp :: (Bool -> Bool) -> Val
liftBoolUnaryOp f = PrimFunc p where
  p [Boolean False] = return $ Boolean $ f False
  p [_] = return $ Boolean $ f True
  p v = throwError $ UnexpectedArgs v

-- TODO
liftCompOp :: (Int -> Int -> Bool) -> Val
liftCompOp f = PrimFunc p where
  p []  = return (Boolean True)
  p [x] = return (Boolean True)
  p vs = Boolean . comp <$> (mapM lowerInt vs) where
      comp [x, y] = f x y
      comp (x:y:xs) = (f x y) && (comp (y:xs))

--- ### Primtive operations

-- Primitive function `car`
-- TODO
car :: [Val] -> EvalState Val
car [List (x:xs)] = return x
car [DottedList (x:xs) y] = return x
car xs = throwError $ UnexpectedArgs xs
-- car [] = throwError (UnexpectedArgs [])
-- car [List(x:xs)] = return x
-- car [(DottedList x y)] = return (head x)
-- car xs = throwError (UnexpectedArgs xs)


-- Primitive function `cdr`
-- TODO
cdr :: [Val] -> EvalState Val
cdr [List(x:xs)] = return (List xs)
cdr [DottedList (x:xs) y] = return (DottedList xs y)
cdr xs = throwError $ UnexpectedArgs xs
-- cdr [] = throwError (UnexpectedArgs [])
-- cdr [List(x:xs)] = return (List xs)
-- cdr [(DottedList (x:xs) y)] = return (DottedList xs y)
-- cdr xs = throwError (UnexpectedArgs xs)


-- Primitive function `cons`
-- TODO
cons :: [Val] -> EvalState Val
cons [x] = return x
cons (x:xs) = (DottedList [x] <$> (cons xs))
cons xs = throwError $ UnexpectedArgs xs
-- cons [x] = return x
-- cons (x:xs) = (DottedList [x] <$> (cons xs))
-- cons xs = throwError (UnexpectedArgs xs)

-------------------------
-- Primitive function `list`
-- TODO
list :: [Val] -> EvalState Val
list [] = return (List [])
list xs = return (flattenList $ List xs)
-- list [] = return (List [])
-- list (x:xs) = return (flattenList (List (x:xs)))

-- Primitive function `append`
append :: [Val] -> EvalState Val
append [] = return $ List []
append [x] = return x
append vv = foldlM append' (List []) (map flattenList vv) where
  append' (List []) x = return x
  append' (List xs) (List ys) = return $ List (xs ++ ys)
  append' (List xs) (DottedList ys y) = return $ DottedList (xs ++ ys) y
  append' _ acc = throwError $ TypeError acc

-- Primitive function `apply`
-- It applies a function to a list of parameters
-- TODO
-- Examples:
--   (apply + '(1 2 3))  => 6
--   (apply car '((1 2 3)))  => 1
applyPrim :: [Val] -> EvalState Val
applyPrim [PrimFunc f, List args] = f args
applyPrim [f, List args] = apply f args  

-- Primitive function `eval`
-- It evaluates the single argument as an expression
-- All you have to do is to check the number of arguments and
-- feed the single argument to the evaluator!
-- TODO
-- Examples:
--   (eval '(+ 1 2 3))  => 6
evalPrim :: [Val] -> EvalState Val
evalPrim [] = eval Void
evalPrim [List x] = eval (List x)
evalPrim [x] = eval x

-- Primitive function `=`, throwing type error for mismatch
-- `=` is a comparison operator for numbers and booleans
-- TODO
-- Examples:
--   (= 1 1) => #t
--   (= #f #t) => #f
--   (= #f #f) => #t
--   (= 'a 10) => Type error
--   (= 'a 'b) => Type error
equalSign :: [Val] -> EvalState Val
equalSign [] = return (Boolean True)
equalSign [x] = return (Boolean True)
equalSign xx 
  | (eqS_helper1 xx) = return (Boolean (eqS_helper2 xx))
  | otherwise = throwError (TypeError (head xx))

eqS_helper1 [] = True
eqS_helper1 [x] = True
eqS_helper1 (x:y:xs) =
  if (((typeName x == "Boolean") || (typeName x == "Number")) && ((typeName x) == (typeName y)))
    then 
      let rest = eqS_helper1 (y:xs)
      in True && rest
    else False

eqS_helper2 [] = True
eqS_helper2 [x] = True
eqS_helper2 ((Number x):(Number y):xs) = ((x == y) && (eqS_helper2 ((Number y):xs)))
eqS_helper2 ((Boolean x):(Boolean y):xs) = ((x == y) && (eqS_helper2 ((Boolean y):xs)))

-- Primitive function `eq?`, not throwing any error
-- `eq?` is a comparison operator for atom values (numbers, booleans, and symbols)
-- Returns `#f` on type mismatch or unsupported types (functions etc)
-- TODO
-- Examples:
--   (eq? 1 1) => #t
--   (eq? #f #t) => #f
--   (eq? #f #f) => #t
--   (eq? 'a 10) => #f
--   (eq? 'a 'a) => #t
eq :: [Val] -> EvalState Val
eq [] = return (Boolean True)
eq [x] = return (Boolean True)
eq xs = 
  let temp = eq_helper xs
  in return (Boolean temp)

eq_helper [] = True
eq_helper [x] = True
eq_helper ((Number x):(Number y):xs) = ((x == y) && (eq_helper ((Number y):xs)))
eq_helper ((Boolean x):(Boolean y):xs) = ((x == y) && (eq_helper ((Boolean y):xs)))
eq_helper ((Symbol x):(Symbol y):xs) = ((x == y) && (eq_helper ((Symbol y):xs)))
eq_helper (x:y:xs) = False

{-eq :: [Val] -> EvalState Val
eq [] = return $ Boolean True
eq [x] = return $ Boolean True
eq vv = return . Boolean $ eq' vv where
  eq' [] = True
  eq' [x] = True
  eq' ((Number x):(Number y):xs) = ((x == y) && (eq' ((Number y):xs)))
  eq' ((Boolean x):(Boolean y):xs) = ((x == y) && (eq' ((Boolean y):xs)))
  eq' ((Symbol x):(Symbol y):xs) = ((x == y) && (eq' ((Symbol y):xs)))
  eq' (x:y:xs) = False-}

-- Primitive function `list?` predicate
-- `(list? arg)` determines whether `arg` is a non-dotted list
-- or an empty list (null)
-- TODO
isList :: [Val] -> EvalState Val
isList [x] = case flattenList x of 
  List _ -> return (Boolean True)
  _      -> return (Boolean False)
isList xs = throwError (UnexpectedArgs xs)


-- Primitive function `symbol?` predicate
-- TODO
isSymbol :: [Val] -> EvalState Val
isSymbol [x] = case x of 
  Symbol _ -> return (Boolean True)
  _        -> return (Boolean False)
isSymbol xs = throwError (UnexpectedArgs xs)

-- Primitive function `pair?` predicate
-- Any `List` or `DottedList` is a pair
-- TODO
isPair :: [Val] -> EvalState Val
isPair [] = throwError (UnexpectedArgs [])
isPair [x, y] = throwError $ UnexpectedArgs [x, y]
isPair [x] = case flattenList x of 
  List [] -> return (Boolean False)
  List _ -> return (Boolean True)
  DottedList _ _ -> return (Boolean True)
  _ -> return (Boolean False)
isPair xs = throwError $ UnexpectedArgs xs

-- Primitive function `number?` predicate
-- TODO
isNumber :: [Val] -> EvalState Val
isNumber [Number _] = return (Boolean True)
isNumber [_] = return (Boolean False)
isNumber xs = throwError $ UnexpectedArgs xs


-- Primitive function `boolean?` predicate
-- TODO
isBoolean :: [Val] -> EvalState Val
isBoolean [Boolean _] = return (Boolean True)
isBoolean [_] = return (Boolean False)
isBoolean xs = throwError (UnexpectedArgs xs)

-- Primitive function `null?` predicate
-- An empty list or its *equivalent* value is null
-- Note: Think about what's equivalent
-- TODO
isNull :: [Val] -> EvalState Val
isNull [x] = case x of 
  List [] -> return (Boolean True)
  _ -> return (Boolean False)
isNull xs = throwError (UnexpectedArgs xs) 

--- ### Runtime
runtime :: Env
runtime = H.fromList [ ("+", liftIntVargOp (+) 0)
                     , ("-", liftIntVargOp (-) 0)
                     , ("*", liftIntVargOp (*)  1)
                     , ("/", liftIntVargOp (div) 1)
                     , ("and", liftBoolVargOp and)
                     , ("or", liftBoolVargOp or)
                     , ("<", liftCompOp (<))
                     , (">", liftCompOp (>))
                     , (">=", liftCompOp (>=))
                     , ("<=", liftCompOp (<=))
                     , ("car", PrimFunc car)
                     , ("cdr", PrimFunc cdr)
                     , ("cons", PrimFunc cons)
                     , ("list", PrimFunc list)
                     , ("not", liftBoolUnaryOp not)
                     , ("=", PrimFunc equalSign)
                     , ("eq?",PrimFunc eq)
                     , ("modulo", liftIntBinOp mod)
                     , ("abs", liftIntUnaryOp abs)
                     , ("append", PrimFunc append)
                     , ("symbol?", PrimFunc isSymbol)
                     , ("list?", PrimFunc isList)
                     , ("pair?", PrimFunc isPair)
                     , ("number?", PrimFunc isNumber)
                     , ("boolean?", PrimFunc isBoolean)
                     , ("null?", PrimFunc isNull)
                     , ("apply", PrimFunc applyPrim)
                     , ("eval", PrimFunc evalPrim)
                     ]
