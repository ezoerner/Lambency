module Graphics.Rendering.Lambency.Material (
  Material(..),
  getShader,
  getShaderMap,
  createSimpleMaterial,
  createTexturedMaterial,
  createSpotlightMaterial,
  getMaterialVar,
  switchTexture,
  beforeRender,
  afterRender,
  destroyMaterial,
) where

--------------------------------------------------------------------------------
import qualified Graphics.Rendering.OpenGL as GL

import Graphics.Rendering.Lambency.Camera
import Graphics.Rendering.Lambency.Shader
import Graphics.Rendering.Lambency.Texture

import Data.Vect.Float

import qualified Data.Map as Map
--------------------------------------------------------------------------------

-- Material consists of a shader and the variables specified by the
-- engine for the shader. If the material has a render texture associated with
-- it, then a MultiMaterial allows the specification of a default material for
-- all objects to use during the off-screen rendering pass of the material
data Material = Material Shader ShaderMap
              | MultiMaterial (Maybe Material) Material
                deriving(Show, Eq)

getShader :: Material -> Shader
getShader (Material s _) = s
getShader (MultiMaterial _ m) = getShader m

getShaderMap :: Material -> ShaderMap
getShaderMap (Material _ m) = m
getShaderMap (MultiMaterial _ m) = getShaderMap m

getMaterialVar :: Material -> String -> ShaderVar
getMaterialVar m = (Map.!) $ (getShaderVars . getShader) m

createSimpleMaterial :: IO(Material)
createSimpleMaterial =
  createSolidTexture (255, 0, 255, 255) >>= createTexturedMaterial

createTexturedMaterial :: Texture -> IO(Material)
createTexturedMaterial tex = do
  shdr <- createSimpleShader
  let varMap = getShaderVars shdr
      shdrMap = Map.singleton (varMap Map.! "diffuseTex") (TextureVal tex)
  return $ Material shdr shdrMap

createSpotlightMaterial :: Maybe Texture -> IO(Material)
createSpotlightMaterial mtex = do
  shdr <- createSpotlightShader
  t <- case mtex of
    Nothing -> createSolidTexture (255, 0, 255, 255)
    Just tex -> return tex
  let lightPos = 10 *& (Vec3 (-1) 1 0)
      lightDir = mkNormal (neg lightPos)
      lightCam = mkPerspCamera lightPos lightDir (mkNormal vec3Z) (pi / 4) 1 0.1 500.0
  depthTex <- createDepthTexture lightCam
  let varMap = getShaderVars shdr
      shdrMap = Map.fromList [
        (varMap Map.! "shadowMap", TextureVal depthTex),
        (varMap Map.! "shadowVP", Matrix4Val $ getViewProjMatrix lightCam),
        (varMap Map.! "diffuseTex", TextureVal t),
        (varMap Map.! "lightDir", Vector3Val $ fromNormal lightDir),
        (varMap Map.! "lightPos", Vector3Val lightPos),
        (varMap Map.! "ambient", Vector3Val $ Vec3 0.15 0.15 0.15)]
  minShdr <- createMinimalShader
  return $ MultiMaterial (Just $ Material minShdr Map.empty) (Material shdr shdrMap)

destroyMaterial :: Material -> IO ()
destroyMaterial (Material shdr shdrMap) = do
  destroyShader shdr
  mapM_ destroyTexture $ concat $ map getTexture (Map.elems shdrMap)
  where getTexture :: ShaderValue -> [Texture]
        getTexture (TextureVal t) =  [t]
        getTexture _ = [] 
destroyMaterial (MultiMaterial mmat mat) = do
  destroyMaterial mat
  case mmat of
    Nothing -> return ()
    Just m -> destroyMaterial m

switchTexture :: Material -> String -> Texture -> Material
switchTexture (Material shdr shdrMap) name tex =
  let shdrVar = (getShaderVars shdr) Map.! name
      shdrVal = TextureVal tex
  in
   Material shdr $ Map.adjust (\_ -> shdrVal) shdrVar shdrMap
switchTexture (MultiMaterial _ m) name tex = switchTexture m name tex

beforeRender :: Material -> IO ()
beforeRender (Material shdr _) = do
  -- Enable the program
  GL.currentProgram GL.$= Just (getProgram shdr)

  -- Enable each vertex attribute that this material needs
  mapM_ enableAttribute $ (Map.elems . getShaderVars) shdr
  where enableAttribute :: ShaderVar -> IO ()
        enableAttribute v = case v of
          Uniform _ _ -> return ()
          Attribute _ loc -> GL.vertexAttribArray loc GL.$= GL.Enabled
-- !FIXME! This doesn't really fit here, which probably means that
-- the 'multi-render' material doesn't belong
beforeRender (MultiMaterial _ m) = beforeRender m

afterRender :: Material -> IO ()
afterRender (Material shdr _) = do
  -- Disable each vertex attribute that this material needs
  mapM_ disableAttribute $ (Map.elems . getShaderVars) shdr
  where disableAttribute :: ShaderVar -> IO ()
        disableAttribute v = case v of
          Uniform (TextureTy unit) _ -> do
            GL.activeTexture GL.$= GL.TextureUnit unit
            GL.textureBinding GL.Texture2D GL.$= Nothing
          Uniform _ _ -> return ()
          Attribute _ loc -> GL.vertexAttribArray loc GL.$= GL.Disabled
-- !FIXME! This doesn't really fit here, which probably means that
-- the 'multi-render' material doesn't belong
afterRender (MultiMaterial _ m) = afterRender m
