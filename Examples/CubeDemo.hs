module Main (main) where

--------------------------------------------------------------------------------

import qualified Graphics.UI.Lambency as L
import qualified Graphics.Rendering.Lambency as LR

import Data.Vect.Float
import Data.Vect.Float.Util.Quaternion

import System.FilePath
import Paths_lambency_examples

import qualified Control.Wire as W
---------------------------------------------------------------------------------

initialCam :: LR.Camera
initialCam = LR.mkPerspCamera
             -- Pos           Dir              Up
             ((-15) *& vec3Z) (mkNormal vec3Z) (mkNormal vec3Y)
             (pi / 4) (4.0 / 3.0)
             -- near far
             0.1 1000.0

demoCam :: LR.GameWire () LR.Camera
-- demoCam = LR.mkDebugCam initialCam
demoCam = LR.mkFixedCam initialCam

planeWire :: IO (LR.Transform, LR.RenderObject)
planeWire = do
  tex <- LR.createSolidTexture (128, 128, 128, 255)
  ro <- LR.createRenderObject LR.plane (LR.createTexturedMaterial tex)
  return (xform, ro)
  where xform = LR.uniformScale 10 $
                LR.translate (Vec3 0 (-2) 0) $
                LR.identity

cubeWire :: IO (LR.GameWire () ())
cubeWire = do
  sound <- getDataFileName ("stereol" <.> "wav") >>= L.loadSound
  (Just tex) <- getDataFileName ("crate" <.> "png") >>= LR.loadTextureFromPNG
  ro <- LR.createRenderObject LR.cube (LR.createTexturedMaterial tex)
  return $ playSound sound 3.0 $ LR.mkObject ro (rotate initial)
  where
    playSound :: L.Sound -> Float -> LR.GameWire a a -> LR.GameWire a a
    playSound sound period wire =
      LR.onEvent (W.periodic period) (\_ -> LR.SoundAction sound L.StartSound) wire

    rotate :: Monad m => LR.Transform -> W.Wire LR.Timestep e m a LR.Transform
    rotate xform =
      W.mkPure (\(W.Timed dt ()) _ -> let
                   newxform = LR.rotateWorld (rotU vec3Y (3.0 * dt)) xform
                   in (Right newxform, rotate newxform))

    initial :: LR.Transform
    initial = LR.rotate (rotU (Vec3 1 0 1) 0.6) LR.identity

initGame :: IO (LR.Game ())
initGame = do
  plane <- planeWire
  cube <- cubeWire
  let lightPos = 10 *& (Vec3 (-1) 1 0)
  spotlight <- LR.createSpotlight lightPos (mkNormal $ neg lightPos) 0
  return $ LR.Game { LR.staticLights = [spotlight],
                     LR.staticGeometry = [plane],
                     LR.mainCamera = demoCam,
                     LR.dynamicLights = [],
                     LR.gameLogic = cube }

main :: IO ()
main = do
  m <- L.makeWindow 640 480 "Cube Demo"
  game <- initGame
  case m of
    (Just win) -> L.run win () game
    Nothing -> return ()
  L.destroyWindow m
