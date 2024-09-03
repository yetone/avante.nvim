function avante#build(...) abort
  let l:source = get(a:, 1, v:true)
  return join(luaeval("require('avante').build(_A)", l:source), "\n")
endfunction
