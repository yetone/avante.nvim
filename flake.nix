{
  description = "Development shell for avante.nvim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?rev=28ace32529a63842e4f8103e4f9b24960cf6c23a";
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      forAllSystems = lib.genAttrs systems;

      ragWorkspace = uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = ./py/rag-service;
      };

      ragOverlay = ragWorkspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      ragOverrides = final: prev: {
        "rag-service" = prev."rag-service".overrideAttrs (_old: {
          src = lib.fileset.toSource {
            root = ./py/rag-service;
            fileset = lib.fileset.unions [
              ./py/rag-service/pyproject.toml
              ./py/rag-service/README.md
              (lib.fileset.fileFilter (file: file.hasExt "py") ./py/rag-service/src)
            ];
          };
        });

        docx2txt = prev.docx2txt.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ final.resolveBuildSystem {
            setuptools = [ ];
          };
        });

        pypika = prev.pypika.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ final.resolveBuildSystem {
            setuptools = [ ];
          };
        });
      };

      ragPythonSets = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          python = pkgs.python311;
        in
        (pkgs.callPackage pyproject-nix.build.packages { inherit python; }).overrideScope (
          lib.composeManyExtensions [
            pyproject-build-systems.overlays.wheel
            ragOverlay
            ragOverrides
          ]
        )
      );
    in
    {
      packages = forAllSystems (
        system:
        let
          pythonSet = ragPythonSets.${system};
          ragService = (pythonSet.mkVirtualEnv "rag-service-env" ragWorkspace.deps.default).overrideAttrs (
            _old: {
              venvIgnoreCollisions = [
                "bin/fastapi"
                "bin/llama-parse"
              ];
            }
          );
        in
        {
          inherit ragService;
          default = ragService;
        }
      );

      apps = forAllSystems (system: {
        rag-service = {
          type = "app";
          program = "${self.packages.${system}.ragService}/bin/rag-service";
        };
        default = self.apps.${system}.rag-service;
      });

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
              pre-commit
            ];

            shellHook = ''
              echo "Welcome to the avante development environment!"
              export DEPS_PATH="target/tests/deps"
            '';
          };

        in
        {
          inherit default;
          ci = let
            neovimTested = pkgs.wrapNeovimUnstable pkgs.neovim-unwrapped {
              plugins = [
                pkgs.vimPlugins.plenary-nvim
              ];
            };
          in
            default.overrideAttrs(oa: {
            buildInputs = oa.buildInputs ++ [
              neovimTested
            ];
            shellHook = oa.shellHook + ''
              export VIMRUNTIME=${pkgs.neovim-unwrapped}/share/nvim/runtime
              '';
          });
        }
      );
    };
}
