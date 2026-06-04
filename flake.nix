{
  description = "Development shell for avante.nvim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?rev=28ace32529a63842e4f8103e4f9b24960cf6c23a";
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

            # not needed (yet), hopefully
            lp.busted
            lp.luarocks
            lp.nlua
          ]);

          default = pkgs.mkShell {
            name = "avante";

            packages = with pkgs; [
              lua5_1.pkgs.luacheck
              lua-language-server
              ripgrep
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
              export DEPS_PATH="target/tests/deps"
            '';
          };

        in
        {
          inherit default;
          ci = default.overrideAttrs(oa: {
            buildInputs = oa.buildInputs ++ [
              pkgs.neovim-unwrapped
            ];
          });
        }
      );
    };
}
