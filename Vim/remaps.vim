"nnoremap <S-space> i
"inoremap <S-space> <Esc>
inoremap jk <ESC>

" Split line
:nnoremap K i<CR><Esc>

" Surround simulating bindings
nnoremap s) ciw(<C-r>")<Esc>
nnoremap s] ciw[<C-r>"]<Esc>
nnoremap s} ciw{<C-r>"}<Esc>
nnoremap s> ciw<lt><C-r>"><Esc>
nnoremap s" ciw"<C-r>""<Esc>
nnoremap s' ciw'<C-r>"'<Esc>
nnoremap sw) ciW(<C-r>")<Esc>
nnoremap sw] ciW[<C-r>"]<Esc>
nnoremap sw} ciW{<C-r>"}<Esc>
nnoremap sw> ciW<lt><C-r>"><Esc>
nnoremap sw" ciW"<C-r>""<Esc>
nnoremap sw' ciW'<C-r>"'<Esc>

" Surround delete bindings
nnoremap ds) vi(dvhp
nnoremap ds] vi[dvhp
nnoremap ds} vi{dvhp
nnoremap ds> vi<dvhp
nnoremap ds" vi"dvhp
nnoremap ds' vi'dvhp

" Surround change bindings
nnoremap cs"' vi"oh<Esc>msvi"l<Esc>cl'<Esc>`scl'<Esc>
nnoremap cs'" vi'oh<Esc>msvi'l<Esc>cl"<Esc>`scl"<Esc>

" Surround visual selected text
vnoremap S" c"<C-r>""<Esc>
vnoremap S' c"<C-r>"'<Esc>
vnoremap S) c(<C-r>")<Esc>
vnoremap S] c[<C-r>"]<Esc>
vnoremap S} c{<C-r>"}<Esc>
vnoremap S> c<lt><C-r>"><Esc>
vnoremap S* c/*<C-r>"*/<Esc>
"vnoremap St c<lt>div><CR><C-r>"<Esc>
" Surround in div tag and edit tag
vnoremap St c<lt>div><CR><C-r>"<Esc>`<lt>lcw

nmap <F3> i<C-R>=strftime("%Y-%m-%d %a %H:%M")<CR><Esc>
imap <F3> <C-R>=strftime("%Y-%m-%d %a %H:%M")<CR>
