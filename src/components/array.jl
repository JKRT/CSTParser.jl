"""
    parse_array(ps)
Having hit '[' return either:
+ A vect
+ A vcat
+ A comprehension
+ An array (vcat of hcats)
"""
function parse_array(ps::ParseState)
    startbyte = ps.t.startbyte
    puncs = INSTANCE[INSTANCE(ps)]
    format_lbracket(ps)

    if ps.nt.kind == Tokens.RSQUARE
        next(ps)
        push!(puncs, INSTANCE(ps))
        format_rbracket(ps)

        return EXPR(VECT, [], ps.nt.startbyte - startbyte, puncs)
    else
        @catcherror ps startbyte first_arg = @default ps @closer ps square @closer ps ws parse_expression(ps)

        # Handle macros
        if first_arg isa LITERAL{Tokens.MACRO}
            first_arg = EXPR(MACROCALL, [first_arg], first_arg.span)
            @default ps @closer ps square while !closer(ps)
                @catcherror ps startbyte a = @closer ps ws parse_expression(ps)
                push!(first_arg.args, a)
                first_arg.span += a.span
            end
        end
        # Handle generator split over lines
        if ps.nt.kind == Tokens.FOR && ps.ws.kind == NewLineWS
            @catcherror ps startbyte first_arg = parse_compound(ps, first_arg)
            if ps.nt.kind != Tokens.RSQUARE
                error("expected \"]\"")
            end
        end
        
        if ps.nt.kind == Tokens.RSQUARE
            if first_arg isa EXPR && first_arg.head == TUPLE
                first_arg.head = VECT

                unshift!(first_arg.punctuation, first(puncs))
                next(ps)
                push!(first_arg.punctuation, INSTANCE(ps))
                format_rbracket(ps)

                first_arg.span = ps.nt.startbyte - startbyte
                return first_arg
            elseif first_arg isa EXPR && first_arg.head == GENERATOR
                next(ps)
                push!(puncs, INSTANCE(ps))
                format_rbracket(ps)

                if first_arg.args[1] isa EXPR && first_arg.args[1].head isa OPERATOR{1, Tokens.PAIR_ARROW}
                    return EXPR(DICT_COMPREHENSION, [first_arg], ps.nt.startbyte - 
                    startbyte, puncs)
                else
                    return EXPR(COMPREHENSION, [first_arg], ps.nt.startbyte - 
                    startbyte, puncs)
                end
            elseif ps.ws.kind== SemiColonWS
                next(ps)
                push!(puncs, INSTANCE(ps))
                format_rbracket(ps)

                return EXPR(VCAT, [first_arg], ps.nt.startbyte - startbyte, puncs)
            else
                next(ps)
                push!(puncs, INSTANCE(ps))
                format_rbracket(ps)

                ret = EXPR(VECT, [first_arg], ps.nt.startbyte - startbyte, puncs)
            end
        elseif ps.ws.kind == SemiColonWS
            ret = EXPR(VCAT,[first_arg], -startbyte, puncs)
            @default ps @closer ps square @closer ps ws @closer ps comma while ps.ws.kind == SemiColonWS
                if ps.nt.kind == Tokens.COMMA
                    error("unexpected comma in matrix expression")
                end
                @catcherror ps startbyte arg = parse_expression(ps)
                push!(ret.args, arg)
            end
            next(ps)
            push!(ret.punctuation, INSTANCE(ps))
            format_rbracket(ps)

            ret.span = ps.nt.startbyte - startbyte
            return ret
        elseif ps.ws.kind == NewLineWS
            ret = EXPR(VCAT, [first_arg], - startbyte, puncs)
            while ps.nt.kind != Tokens.RSQUARE
                @catcherror ps startbyte a = @default ps @closer ps square parse_expression(ps)
                push!(ret.args, a)
            end
            next(ps)
            push!(ret.punctuation, INSTANCE(ps))
            format_rbracket(ps)
            
            ret.span += ps.nt.startbyte
            return ret
        elseif ps.ws.kind == WS
            first_row = EXPR(HCAT, [first_arg], -(ps.nt.startbyte - first_arg.span))
            while ps.nt.kind != Tokens.RSQUARE && ps.ws.kind != NewLineWS && ps.ws.kind != SemiColonWS
                @catcherror ps startbyte a = @default ps @closer ps square @closer ps ws parse_expression(ps)
                push!(first_row.args, a)
            end
            first_row.span += ps.nt.startbyte
            if ps.nt.kind == Tokens.RSQUARE
                next(ps)
                push!(puncs, INSTANCE(ps))
                first_row.punctuation = puncs
                first_row.span += first(puncs).span + last(puncs).span
                return first_row
            else
                first_row.head = ROW
                ret = EXPR(VCAT, [first_row], 0)
                while ps.nt.kind != Tokens.RSQUARE
                    @catcherror ps startbyte first_arg = @default ps @closer ps square @closer ps ws parse_expression(ps)
                    push!(ret.args, EXPR(ROW, [first_arg], first_arg.span))
                    while ps.nt.kind != Tokens.RSQUARE && ps.ws.kind != NewLineWS && ps.ws.kind != SemiColonWS
                        @catcherror ps startbyte a = @default ps @closer ps square @closer ps ws parse_expression(ps)
                        push!(last(ret.args).args, a)
                        last(ret.args).span += a.span
                    end
                    # last(ret.args).span += ps.nt.startbyte
                end
                next(ps)
                push!(puncs, INSTANCE(ps))
                ret.punctuation = puncs
                ret.span = ps.nt.startbyte - startbyte
                return ret
            end
        end
    end
end

_start_vect(x::EXPR) = Iterator{:vect}(1, length(x.args) + length(x.punctuation))

_start_vcat(x::EXPR) = Iterator{:vcat}(1, length(x.args) + length(x.punctuation))
_start_hcat(x::EXPR) = Iterator{:hcat}(1, length(x.args) + length(x.punctuation))
_start_row(x::EXPR) = Iterator{:row}(1, length(x.args))

_start_typed_vcat(x::EXPR) = Iterator{:typed_vcat}(1, length(x.args) + length(x.punctuation))


function next(x::EXPR, s::Iterator{:vect})
    if isodd(s.i)
        return x.punctuation[div(s.i + 1, 2)], +s
    elseif s.i == s.n
        return last(x.punctuation), +s
    else
        return x.args[div(s.i, 2)], +s
    end
end

function next(x::EXPR, s::Iterator{:vcat})
    if s.i == 1
        return first(x.punctuation), +s
    elseif s.i == s.n
        return last(x.punctuation), +s
    else
        return x.args[s.i - 1], +s
    end
end

function next(x::EXPR, s::Iterator{:hcat})
    if s.i == 1
        return first(x.punctuation), +s
    elseif s.i == s.n
        return last(x.punctuation), +s
    else
        return x.args[s.i - 1], +s
    end
end

next(x::EXPR, s::Iterator{:row}) = x.args[s.i], +s

function next(x::EXPR, s::Iterator{:typed_vcat})
    if s.i == 1
        return x.args[1], +s
    elseif s.i == 2
        return first(x.punctuation), +s
    elseif s.i == s.n
        return last(x.punctuation), +s
    else
        return x.args[s.i - 1], +s
    end
end