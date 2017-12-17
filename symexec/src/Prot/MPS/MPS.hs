module Prot.MPS.MPS where
import Prot.Lang.Command
import Prot.Lang.Expr
import Prot.Lang.Types
import Prot.Lang.Lang
import qualified Data.Map.Strict as Map

data Party msg = forall st. Party {
    partyState :: st,
    partyReact :: st -> msg -> Dist (st, msg)
                            }

--
-- react = st -> msg -> prog
type MPSSystem msg = (Map.Map String (Party msg))
type MPSScript = [String]
-- runMPS turns 
--

runMPS :: MPSSystem msg -> msg -> [String] -> Dist (MPSSystem msg, msg)
runMPS system curmsg (x : xs) = 
    case (Map.lookup x system) of
      (Just party) -> 
          case party of
            (Party pst preact) -> do
              (newst, newmsg) <- preact pst curmsg
              runMPS (Map.insert x (Party newst preact) system) newmsg xs
      _ -> fail "bad x"

runMPS system curmsg [] = return (system, curmsg)



