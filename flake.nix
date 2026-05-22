{
  description = "Development shell for avante.nvim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          mylua = pkgs.lua5_1.withPackages (lp: [
            lp.luassert
            lp.busted
            lp.luarocks
            lp.nlua
          ]);
        in
        {
          default = pkgs.mkShell {
            name = "avante";

            packages = with pkgs; [
              lua5_1.pkgs.luacheck
              lua-language-server
              yq
              silver-searcher
              python3
              docker
              stylua
              mylua
              vimcats
            ];

            shellHook = ''
              echo "Welcome to the avante development environment!"
              export DEPS_PATH="$PWD/target/tests"
            '';
          };
        }
      );
    };
}
