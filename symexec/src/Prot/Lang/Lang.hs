module Prot.Lang.Lang where
import Prot.Lang.Command
import Prot.Lang.Expr
import Prot.Lang.Types
import Prot.Lang.Analyze
import Control.Monad.Except
import Data.Type.Equality
import Data.Parameterized.Some
import Control.Monad.State
import qualified Prot.Prove.SMT as SMT
import Control.Monad.Free

-- I need a better translation language.

data DistF k where
    DSamp :: Distr tp -> [SomeExp] -> (Expr tp -> k) -> DistF k
    DIte :: Expr TBool -> k -> k -> DistF k


instance Functor DistF where
    fmap f (DSamp d es k) = DSamp d es (f . k)
    fmap f (DIte e k1 k2) = DIte e (f k1) (f k2)

type Dist = Free DistF

data SomeDist = forall tp. SomeDist (TypeRepr tp) (Dist (Expr tp))

sizeOfDist :: Dist (Expr tp) -> Integer
sizeOfDist (Pure e) = 1
sizeOfDist (Free (DSamp d args k)) = (sizeOfDist $ k (mkAtom "0" (typeOf d)))
sizeOfDist (Free (DIte b k1 k2)) = (sizeOfDist k1) + (sizeOfDist k2)

distType :: Dist (Expr tp) -> TypeRepr tp
distType (Pure e) = typeOf e
distType (Free (DSamp d _ k)) = distType $ k (mkAtom "0" (typeOf d))
distType (Free (DIte _ k _)) = distType k

dSamp :: Distr tp -> [SomeExp] -> Dist (Expr tp)
dSamp d args = liftF $ DSamp d args id

dIte :: Expr TBool -> Dist a -> Dist a -> Dist a
dIte x k1 k2 =
    wrap $ DIte x (k1) (k2)

compileDist' :: Dist (Expr tp) -> State Int (Command tp)
compileDist' (Pure e) = return $ Ret e
compileDist' (Free (DSamp d args k)) = do
    n <- freshName
    cont <- compileDist' (k (mkAtom n (typeOf d)))
    return $ Sampl n d args cont
compileDist' (Free (DIte b k1 k2)) = do
    cont1 <- compileDist' k1
    cont2 <- compileDist' k2
    return $ Ite b cont1 cont2

compileDist :: Dist (Expr tp) -> (Command tp, Int)
compileDist d = runState (compileDist' d) 0

freshName :: State Int String
freshName = do
    x <- get
    put $ (x + 1)
    return $ "x" ++ (show x)


ppDist :: Dist (Expr tp) -> String
ppDist p =
    let (c, _) = compileDist p in
    ppCommand c

ppDistLeaves :: Dist (Expr tp) -> IO String
ppDistLeaves p = do
    let (c,_) = compileDist p 
    lvs <- commandToLeaves SMT.condSatisfiable c
    return $ ppLeaves lvs

getDistVarIdx :: Dist (Expr tp) -> Int
getDistVarIdx d =
    let (_, i) = compileDist d in i

--- abbreviations

unifBool = dSamp unifBoolDistr []
unifInt x y = dSamp (unifIntDistr x y) []

dSwitch :: ExprEq (Expr a) => Expr a -> Dist b -> [(Expr a, Dist b)] -> Dist b
dSwitch e def [] = def
dSwitch e def ((cond,a):as) =
    dIte (e |==| cond) a (dSwitch e def as)

unifElt :: [a] -> Dist a
unifElt [] = error "empty unif"
unifElt es = do
    i <- unifInt 0 (fromIntegral (length es - 1))
    dSwitch i (return (head es)) $ map (\(i,e) -> (intLit i, return e)) (zip (map fromIntegral [0..(length es - 1)]) es)
