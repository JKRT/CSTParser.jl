using CSTParser
using Test

import CSTParser: parse, remlineinfo!, span, flisp_parse, typof, kindof, valof

include("parser.jl")
include("interface.jl")
CSTParser.check_base()
