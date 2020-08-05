
call plug#begin('~/.config/nvim/autoload/plugged')
    " Git Status
    Plug 'tpope/vim-fugitive'
    Plug 'jiangmiao/auto-pairs'
    Plug 'neoclide/coc.nvim', {'branch': 'release'}
    Plug 'preservim/nerdtree', { 'on':  'NERDTreeToggle' }
    Plug 'mhinz/vim-startify'
call plug#end()

syntax on
set nowrap " вырубает перенос строк 
set number
set relativenumber
set showmatch
set smartindent
set background=dark
set t_Co=256 
set shiftwidth=4 " размер отступов (нажатие на << или >>)
set tabstop=4 " ширина табуляции
set softtabstop=4 " ширина 'мягкого' таба
set autoindent " ai - включить автоотступы (копируется отступ предыдущей строки)
set cindent " ci - отступы в стиле С
set expandtab " преобразовать табуляцию в пробелы
set ruler
set smartindent " Умные отступы (например, автоотступ после {)
"colorscheme hybrid
hi Normal ctermbg=none
