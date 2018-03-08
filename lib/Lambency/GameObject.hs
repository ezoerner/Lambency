module Lambency.GameObject (
  wireFrom,
  bracketResource, liftWire, withResource, joinResources, withDefault,
  mkContWire, stepContWire,
  doOnce, doOnceWithInput,
  quitWire,
  mkObject,
  staticObject,
  withVelocity,
  pulseSound
) where

--------------------------------------------------------------------------------
import Control.Arrow
import Control.Monad
import Control.Monad.Reader
import Control.Wire

import Data.Maybe
import Data.Either (isLeft)
import Data.Foldable

import Lambency.Render
import Lambency.Sound
import Lambency.Transform
import Lambency.Types

import Prelude hiding ((.), id)

import qualified Graphics.UI.GLFW as GLFW
import FRP.Netwire.Input

import Linear.Vector
--------------------------------------------------------------------------------

wireFrom :: GameMonad a -> (a -> GameWire b c) -> GameWire b c
wireFrom prg fn = mkGen $ \dt val -> do
  seed <- prg
  stepWire (fn seed) dt (Right val)

doOnce :: GameMonad () -> GameWire a a
doOnce pgm = wireFrom pgm $ const Control.Wire.id

doOnceWithInput :: (a -> GameMonad ()) -> GameWire a a
doOnceWithInput fn = mkGenN $ \x -> fn x >> return (Right x, mkId)

mkObject :: RenderObject -> GameWire a Transform -> GameWire a a
mkObject ro xfw = mkGen $ \dt val -> do
  (xform, nextWire) <- stepWire xfw dt (Right val)
  case xform of
    Right xf -> addRenderAction xf ro >> return (Right val, mkObject ro nextWire)
    Left i -> return (Left i, mkObject ro nextWire)

staticObject :: RenderObject -> Transform -> GameWire a a
staticObject ro = mkObject ro . mkConst . Right

withVelocity :: (Monad m, Monoid s) =>
                Transform -> Wire (Timed Float s) e m a Vec3f ->
                Wire (Timed Float s) e m a Transform
withVelocity initial velWire = velWire >>> (moveXForm initial)
  where moveXForm :: (Monad m, Monoid s) =>
                     Transform -> Wire (Timed Float s) e m Vec3f Transform
        moveXForm xf = mkPure $ \t vel -> let
          newxform = translate (dtime t *^ vel) xf
          in (Right newxform, moveXForm newxform)

pulseSound :: Sound -> GameWire a a
pulseSound = doOnce . startSound

-- | Runs the initial loading program and uses the resource until the generated
-- wire inhibits, at which point it unloads the resource. Once the resource is
-- freed, the resulting wire returns Nothing indefinitely. The resulting wire
-- also takes a signal to terminate from its input.
bracketResource :: IO r -> (r -> IO ()) -> ResourceContextWire r a b
                -> ContWire (a, Bool) (Maybe b)
bracketResource load unload (RCW rcw) = CW $ mkGen $ \dt x -> do
  -- TODO: Maybe should restrict this to certain types of resources?
  resource <- GameMonad $ liftIO load
  stepWire (go resource rcw) dt (Right x)
    where
      go res w = mkGen $ \dt (x, quitSignal) ->
        let quit = do
              GameMonad $ liftIO (unload res)
              return (Right Nothing, pure Nothing)
        in if quitSignal then quit else do
          (result, w') <- runReaderT (stepWire w dt (Right x)) res
          if isLeft result then quit else return (Just <$> result, go res w')

liftWire :: GameWire a b -> ResourceContextWire r a b
liftWire gw = RCW $ mkGen $ \dt x -> do
  (r, RCW gw') <- second liftWire <$> (ReaderT $ \_ -> stepWire gw dt (Right x))
  return (r, gw')

withResource :: (r -> GameWire a b) -> ResourceContextWire r a b
withResource wireGen = RCW $ mkGen $ \dt x -> do
  (r, RCW w) <- second liftWire <$>
                (ReaderT $ \r -> stepWire (wireGen r) dt (Right x))
  return (r, w)

joinResources :: Monoid b
              => [ContWire (a, Bool) (Maybe b)]
              -> ContWire (a, Bool) (Maybe b)
joinResources = mkWire . fmap msequence . sequenceA
  where
    mkWire (CW w) = CW $ mkGen $ \dt (x, quit) -> do
      (Right result, w') <- stepWire w dt (Right (x, quit))
      if not quit && isNothing result
        then stepWire w' dt (Right (undefined, True))
        else return (Right result, getContinuousWire . mkWire $ CW w')

    msequence :: (MonadPlus m, Monoid b) => [m b] -> m b
    msequence [] = mzero
    msequence (v : vs) = foldr (\x y -> x >>= ((<$> y) . mappend)) v vs

withDefault :: GameWire a b -> ContWire a b -> ContWire a b
withDefault w (CW m) = CW $ w <|> m

mkContWire :: (TimeStep -> a -> GameMonad (b, ContWire a b)) -> ContWire a b
mkContWire f = CW $ mkGen $ \dt x -> do
  (r, CW w') <- f dt x
  return (Right r, w')

stepContWire :: ContWire a b -> TimeStep -> a -> GameMonad (b, ContWire a b)
stepContWire (CW w) dt x = do
  (Right r, w') <- stepWire w dt (Right x)
  return (r, CW w')

-- Wire that behaves like the identity wire until the given key
-- is pressed, then inhibits forever.
quitWire :: GLFW.Key -> GameWire a a
quitWire key =
  rSwitch mkId . (mkId &&& (now . pure mkEmpty . keyPressed key <|> never))
