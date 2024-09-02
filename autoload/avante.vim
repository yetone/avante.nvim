function avante#build() abort
  return join(luaeval("require('avante').build()"), "\n")
endfunction
