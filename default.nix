{ pkgs ? import <nixpkgs> {} }:
let
  inherit (pkgs.haskell.packages) ghcjsHEAD;

  # Running off fork for now
  miso-src = pkgs.fetchFromGitHub {
    rev = "3f614f255961bb7ed92f0b24a292acf5e6287b34";
    sha256 = "0ynljfp6wh3qgfllk3afc8rykqlgjkq67nrmgmcq8f3xqrmavi4p";
    owner = "FPtje";
    repo = "miso";
  };

  miso-ghcjs = ghcjsHEAD.callCabal2nix "miso" miso-src {};

  drv = ghcjsHEAD.callPackage ./pkg.nix { miso = miso-ghcjs; };

  final = pkgs.runCommand "miso-jswidget-example" {} ''
    mkdir $out
    cp ${drv}/bin/main.jsexe/all.js $out/all.js
    cp ${./html-src/index.html} $out/index.html
  '';
in
  if pkgs.lib.inNixShell then drv.env else final
