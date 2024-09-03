" reference: https://github.com/lepture/vim-jinja/blob/master/syntax/jinja.vim

if exists("b:current_syntax")
  finish
endif

if !exists("main_syntax")
  let main_syntax = 'html'
endif

runtime! syntax/html.vim
unlet b:current_syntax

syntax case match

" jinja template built-in tags and parameters
" 'comment' doesn't appear here because it gets special treatment
syn keyword jinjaStatement contained if else elif endif is not
syn keyword jinjaStatement contained for in recursive endfor
syn keyword jinjaStatement contained raw endraw
syn keyword jinjaStatement contained block endblock extends super scoped
syn keyword jinjaStatement contained macro endmacro call endcall
syn keyword jinjaStatement contained from import as do continue break
syn keyword jinjaStatement contained filter endfilter set endset
syn keyword jinjaStatement contained include ignore missing
syn keyword jinjaStatement contained with without context endwith
syn keyword jinjaStatement contained trans endtrans pluralize
syn keyword jinjaStatement contained autoescape endautoescape

" jinja templete built-in filters
syn keyword jinjaFilter contained abs attr batch capitalize center default
syn keyword jinjaFilter contained dictsort escape filesizeformat first
syn keyword jinjaFilter contained float forceescape format groupby indent
syn keyword jinjaFilter contained int join last length list lower pprint
syn keyword jinjaFilter contained random replace reverse round safe slice
syn keyword jinjaFilter contained sort string striptags sum
syn keyword jinjaFilter contained title trim truncate upper urlize
syn keyword jinjaFilter contained wordcount wordwrap

" jinja template built-in tests
syn keyword jinjaTest contained callable defined divisibleby escaped
syn keyword jinjaTest contained even iterable lower mapping none number
syn keyword jinjaTest contained odd sameas sequence string undefined upper

syn keyword jinjaFunction contained range lipsum dict cycler joiner


" Keywords to highlight within comments
syn keyword jinjaTodo contained TODO FIXME XXX

" jinja template constants (always surrounded by double quotes)
syn region jinjaArgument contained start=/"/ skip=/\\"/ end=/"/
syn region jinjaArgument contained start=/'/ skip=/\\'/ end=/'/
syn keyword jinjaArgument contained true false

" Mark illegal characters within tag and variables blocks
syn match jinjaTagError contained "#}\|{{\|[^%]}}\|[&#]"
syn match jinjaVarError contained "#}\|{%\|%}\|[<>!&#%]"
syn cluster jinjaBlocks add=jinjaTagBlock,jinjaVarBlock,jinjaComBlock,jinjaComment

" jinja template tag and variable blocks
syn region jinjaTagBlock start="{%" end="%}" contains=jinjaStatement,jinjaFilter,jinjaArgument,jinjaFilter,jinjaTest,jinjaTagError display containedin=ALLBUT,@jinjaBlocks
syn region jinjaVarBlock start="{{" end="}}" contains=jinjaFilter,jinjaArgument,jinjaVarError display containedin=ALLBUT,@jinjaBlocks
syn region jinjaComBlock start="{#" end="#}" contains=jinjaTodo containedin=ALLBUT,@jinjaBlocks


hi def link jinjaTagBlock PreProc
hi def link jinjaVarBlock PreProc
hi def link jinjaStatement Statement
hi def link jinjaFunction Function
hi def link jinjaTest Type
hi def link jinjaFilter Identifier
hi def link jinjaArgument Constant
hi def link jinjaTagError Error
hi def link jinjaVarError Error
hi def link jinjaError Error
hi def link jinjaComment Comment
hi def link jinjaComBlock Comment
hi def link jinjaTodo Todo

let b:current_syntax = "jinja"
