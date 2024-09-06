function avante#build(...) abort
  let l:source = get(a:, 1, v:false)
  return join([luaeval("require('avante_lib').load()") ,luaeval("require('avante.api').build(_A)", l:source)], "\n")
endfunction
