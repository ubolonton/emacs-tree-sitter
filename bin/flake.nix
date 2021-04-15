{
  description = "Rust development environment";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "nixpkgs/7d71001b796340b219d1bfa8552c81995017544a";
    flake-compat = { url = "github:edolstra/flake-compat"; flake = false; };
    rust-overlay = { url = "github:oxalica/rust-overlay"; inputs.nixpkgs.follows = "nixpkgs"; };
    devshell-flake.url = "github:numtide/devshell";
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, flake-compat, rust-overlay, devshell-flake }:
    { }
    //
    (flake-utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" ]
      (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              self.overlay
              (import rust-overlay)
              devshell-flake.overlay
            ];

            config = { };

          };
        in
        rec {
          packages = {
            inherit (pkgs.rust-bin.nightly.latest)
              default;
          };
          devShell = with pkgs; devshell.mkShell {
            packages = [
              cask
              tree-sitter
              cargo-watch
            ] ++ (with rust-bin.stable.latest; [
              default
            ]);
            env = [
              {
                name = "RUST_SRC_PATH";
                value = "${rust-bin.stable.latest.rust-src}/lib/rustlib/src/rust/library";
              }
              {
                name = "LIBCLANG_PATH";
                value = "${llvmPackages.libclang}/lib";
              }
              {
                name = "DIR";
                prefix = ''
                  $( cd "$(dirname "$\{\BASH_SOURCE [ 0 ]}")"; pwd )
                '';
              }
            ];
            commands = [
              {
                name = "setup";
                command = ''
                  git submodule update --init
                  cask install && cask build
                  cask --path langs install && cask --path langs build
                  $(cd $DIR && bin/ensure-lang rust)
                  make test
                '';
                help = ''
                  setup the tree-sitter environment
                '';
              }
              {
                name = "run-test";
                command = ''
                  $(cd $DIR && make test)
                '';
                help = ''
                  run-test of emacs-tree-sitter
                '';
              }
              {
                name = "run-watch";
                command = ''
                  $(cd $DIR && make watch)
                '';
                help = ''
                  run cargo watch of emacs-tree-sitter
                '';
              }
            ];
          };
        })
    ) //
    {
      overlay = final: prev: { };
    };
}
