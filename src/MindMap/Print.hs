{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE OverloadedStrings #-}
module MindMap.Print where

import Text.Pandoc
import Text.Pandoc.Error
import Text.Pandoc.Walk (walk)
import Data.Maybe
import Debug.Trace
import Data.List
import qualified Data.Map as Map
import Data.String.Interpolate
import System.Process
import System.Directory
import Data.Char (toLower)
import Data.Tree

import MindMap.Data
import Utils

template dta ann cann = [i|
\\documentclass{standalone}
\\usepackage{mathspec}
\\usepackage{fancyvrb}
\\usepackage{etoolbox}
\\usepackage{relsize}
\\usepackage{hyperref}
\\setallmainfonts(Digits,Latin){Fira Sans Light} 
\\setmonofont{Envy Code R}
\\usepackage{tikz}
\\usetikzlibrary{mindmap}
\\usetikzlibrary{positioning}   
\\usetikzlibrary{snakes}
\\usepackage{enumitem}
\\providecommand{\\tightlist}{%
\\setlength{\\itemsep}{0pt}\\setlength{\\parskip}{0pt}
}
\\setlength{\\itemsep}{0pt}\\setlength{\\parskip}{0pt}
\\setlist{leftmargin=3mm}
\\setitemize{itemsep=1mm}
\\let\\tempone\\itemize
\\let\\temptwo\\enditemize
\\renewenvironment{itemize}{\\tempone\\addtolength{\\itemsep}{0.5\\baselineskip}}{\\temptwo}
\\pagestyle{empty}
\\begin{document}
\\setlength\\abovedisplayskip{5pt}
\\setlength\\belowdisplayskip{5pt}
\\setlength\\abovedisplayshortskip{5pt}
\\setlength\\belowdisplayshortskip{5pt}
\\pgfdeclarelayer{background}
\\pgfsetlayers{background,main}  
\\tikzstyle{every annotation}=[fill opacity=0.0, text opacity=1, draw opacity=0.0]
\\begin{tikzpicture}[mindmap, clockwise from=0, every node/.style=concept, concept color=orange!40,
    level 1/.append style={level distance=5cm,sibling angle=90},
    level 2/.append style={level distance=5cm,sibling angle=60},
    level 3/.append style={level distance=5cm,sibling angle=60},
    level 4/.append style={level distance=5cm,sibling angle=60},
    concept connection/.append style={opacity=0.3},
    ]
#{dta};
#{ann};
\\begin{pgfonlayer}{background}
#{cann}\\end{pgfonlayer}
\\end{tikzpicture}
\\end{document}
|]

  

drawStruct :: Structure -> String
drawStruct t = drawTree (fmap f t) where 
   f (Concept idn nm mta c) = nm ++ "-" ++ (show mta) ++ " - " ++ (show c) 

_m node key = Map.lookup key (getHeadingMeta $ rootLabel node)

getConceptNodes :: String -> Tree StructureLeaf -> String
getConceptNodes r node = 
    let contents = concatMap (\x -> getConceptNodes r x) (subForest node)
        identifier = getID $ rootLabel node
        color = case (_m node "color") of
          (Just c) -> [i| color=#{c} |]
          _ -> ""
    in
        if identifier == "root"
          then [i| \\node{#{r}}
  #{contents} |]
          else [i| child[concept #{color}] { node[concept] (#{identifier}) {#{getName $ rootLabel node}}
  #{contents}} |]

getAnnotationText node = expandToLatex (contents node)

_get node d s =
  let v = fromMaybe d (_m node s)
  in case v of
       "-" -> d
       _ -> v

data Direction' = North | South | East | West deriving (Show,Eq)
data Direction = D (Direction', Integer) | NoDirection deriving (Show,Eq)
type Placement = (Direction, Direction)

pempty = (NoDirection, NoDirection)

pmerge :: Placement -> Direction -> Placement
pmerge x NoDirection = x
pmerge (NoDirection, NoDirection) x = (x, NoDirection)

pmerge (D (d1, n1), NoDirection) (D (dx, nx))
  | d1 == dx = (D (d1, n1 + nx), NoDirection)
  | otherwise = (D (d1, n1), D (dx, nx))
  
pmerge (D (d1, n1), D (d2, n2)) (D (dx, nx))
   | d1 == dx = (D (d1, n1 + nx), D (d2, n2))
   | d2 == dx = (D (d1, n1),      D (d2, n2 + nx))
   | otherwise = error "Illegally specified placement - You can specify max 2 different placements"
pmerge _ _ = error "!"

getPlacement' :: Char -> Direction
getPlacement' '<' = D (West, 1)
getPlacement' '>' = D (East, 1)
getPlacement' '^' = D (North, 1)
getPlacement' 'V' = D (South, 1)
getPlacement' _ = NoDirection

getPlacement :: String -> Placement
getPlacement s = let
  dirs = map getPlacement' s
  placement = foldl pmerge pempty dirs
  in placement

toStringTuple :: Placement -> (String -> String)
toStringTuple (NoDirection, NoDirection)     = \x -> [i| right of=#{x}, node distance=5cm|]
toStringTuple (D (North, n1), NoDirection)   = \x -> [i| above of=#{x}, node distance=#{n1}cm|]
toStringTuple (D (South, n1), NoDirection)   = \x -> [i| below of=#{x}, node distance=#{n1}cm|]
toStringTuple (D (East,  n1), NoDirection)   = \x -> [i| right of=#{x}, node distance=#{n1}cm|]
toStringTuple (D (West,  n1), NoDirection)   = \x -> [i| left  of=#{x}, node distance=#{n1}cm|] 
toStringTuple (D (North, n1), D (East,  n2)) = \x -> [i| above right of=#{x}, node distance=#{n1+n2}cm|]
toStringTuple (D (North, n1), D (West,  n2)) = \x -> [i| above  left of=#{x}, node distance=#{n1+n2}cm|]
toStringTuple (D (South, n1), D (East,  n2)) = \x -> [i| below right of=#{x}, node distance=#{n1+n2}cm|]
toStringTuple (D (South, n1), D (West,  n2)) = \x -> [i| below  left of=#{x}, node distance=#{n1+n2}cm|]
toStringTuple (D (East,  n1), D (North, n2)) = \x -> [i| above right of=#{x}, node distance=#{n1+n2}cm|]
toStringTuple (D (East,  n1), D (South, n2)) = \x -> [i| below right of=#{x}, node distance=#{n1+n2}cm|]
toStringTuple (D (West,  n1), D (North, n2)) = \x -> [i| above  left of=#{x}, node distance=#{n1+n2}cm|]
toStringTuple (D (West,  n1), D (South, n2)) = \x -> [i| below  left of=#{x}, node distance=#{n1+n2}cm|]

toStringTuple _ = error "Invalid configuration!"

getTuplePlacement :: String -> (String -> String)
getTuplePlacement = toStringTuple . getPlacement

getAnnotationPosition
  :: Tree StructureLeaf -> (String -> String)
getAnnotationPosition node =
  case _m node "placement" of
    Just v -> (getTuplePlacement v)
    _      -> (getTuplePlacement "")

annotationName :: String -> String
annotationName identifier = identifier ++ "-ann"

getAnnotationsConnections :: Tree StructureLeaf -> String -> String
getAnnotationsConnections node cc =
  let identifier = getID $ rootLabel node
      text       = getAnnotationText (rootLabel node)
  in
    if identifier /= "root" && text /= ""
      then [i|\\draw [concept connection] (#{identifier}) edge (#{annotationName(identifier)}); #{cc} |]
      else cc


nodeToAnnotation :: Tree StructureLeaf -> String -> String
nodeToAnnotation node cc =
  let identifier = getID $ rootLabel node
      text       = getAnnotationText (rootLabel node)
      f          = getAnnotationPosition node
  in
    if identifier /= "root" && text /= ""
      then
        [i|\\node[annotation, #{f(identifier)}]  (#{annotationName(identifier)}) {#{text}}; #{cc} |]
      else
        cc

mapAnnotations :: (Tree StructureLeaf -> String -> String) -> Tree StructureLeaf -> String
mapAnnotations f node =
  let cc = concatMap (mapAnnotations f) (subForest node)
  in f node cc



draw :: String -> String -> IO ()
draw name exp = do
    system "rm -rf .pandoc-mm";
    createDirectory ".pandoc-mm";
    writeFile ".pandoc-mm/mm.tex" $ exp;
    system ("cd .pandoc-mm && xelatex -shell-escape -interaction nonstopmode mm.tex")
    system ("pdfcrop .pandoc-mm/mm.pdf " ++ name);
    return ();

drawMindMap :: String -> MindMap -> IO ()
drawMindMap fn m = draw fn $ asMindMapLatex m

asMindMapLatex :: MindMap -> String
asMindMapLatex m =
  let name = getMindMapName m
      struct = getStructure m
      sStruct = getConceptNodes name struct
      sAnn = mapAnnotations nodeToAnnotation struct
      cAnn = mapAnnotations getAnnotationsConnections struct
  in (template sStruct sAnn cAnn)

printMindMapLatex :: MindMap -> IO ()
printMindMapLatex m = putStrLn $ asMindMapLatex m

printMindMap :: MindMap -> String
printMindMap m = drawStruct (getStructure m)

instance Show MindMap where
  show = printMindMap
