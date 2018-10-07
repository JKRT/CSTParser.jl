
function parse_kw(ps)
    k = ps.t.kind
    if k == Tokens.IF
        return @default ps @closer ps block parse_if(ps)
    elseif k == Tokens.LET
        return @newscope ps @default ps @closer ps block parse_let(ps)
    elseif k == Tokens.TRY
        return @default ps @newscope ps @closer ps block parse_try(ps)
    elseif k == Tokens.FUNCTION
        return @addbinding ps @newscope ps @default ps @closer ps block parse_function(ps)
    elseif k == Tokens.MACRO
        return @addbinding ps @newscope ps @default ps @closer ps block parse_macro(ps)
    elseif k == Tokens.BEGIN
        return @default ps @closer ps block parse_begin(ps)
    elseif k == Tokens.QUOTE
        return @default ps @closer ps block parse_quote(ps)
    elseif k == Tokens.FOR
        return @newscope ps @default ps @closer ps block parse_for(ps)
    elseif k == Tokens.WHILE
        return @newscope ps @default ps @closer ps block parse_while(ps)
    elseif k == Tokens.BREAK
        return INSTANCE(ps)
    elseif k == Tokens.CONTINUE
        return INSTANCE(ps)
    elseif k == Tokens.IMPORT || k == Tokens.IMPORTALL || k == Tokens.USING
        ret = parse_imports(ps)
        push!(ps.meta.imports, Reference(ret, ps.nt.startbyte - ret.fullspan, ps.meta.s, ps.meta.nb, nothing))
        return ret
    elseif k == Tokens.EXPORT
        ret = parse_export(ps)
        push!(ps.meta.exports, Reference(ret, ps.nt.startbyte - ret.fullspan, ps.meta.s, ps.meta.nb, nothing))
        return ret
    elseif k == Tokens.MODULE ||  k == Tokens.BAREMODULE
        return @addbinding ps @newscope ps @default ps @closer ps block parse_module(ps)
    elseif k == Tokens.CONST
        return @default ps parse_const(ps)
    elseif k == Tokens.GLOBAL
        return @default ps parse_global(ps)
    elseif k == Tokens.LOCAL
        return @default ps parse_local(ps)
    elseif k == Tokens.RETURN
        return @default ps parse_return(ps)
    elseif k == Tokens.END
        return parse_end(ps)
    elseif k == Tokens.ELSE || k == Tokens.ELSEIF || k == Tokens.CATCH || k == Tokens.FINALLY
        push!(ps.errors, Error((ps.t.startbyte:ps.t.endbyte) .+ 1 , "Unexpected end."))
        return ErrorToken(IDENTIFIER(ps))
    elseif k == Tokens.ABSTRACT
        return @addbinding ps @newscope ps @default ps parse_abstract(ps)
    elseif k == Tokens.PRIMITIVE
        return @addbinding ps @newscope ps @default ps parse_primitive(ps)
    elseif k == Tokens.TYPE
        return @addbinding ps @newscope ps @default ps @closer ps block parse_struct(ps, true)
    elseif k == Tokens.IMMUTABLE || k == Tokens.STRUCT
        return @addbinding ps @newscope ps @default ps @closer ps block parse_struct(ps, false)
    elseif k == Tokens.MUTABLE
        return @addbinding ps @newscope ps @default ps @closer ps block parse_mutable(ps)
    elseif k == Tokens.OUTER
        return IDENTIFIER(ps)
    end
end
# Prefix 

function parse_const(ps::ParseState)
    kw = KEYWORD(ps)
    arg = parse_expression(ps)

    return EXPR{Const}(Any[kw, arg])
end

function parse_global(ps::ParseState)
    kw = KEYWORD(ps)
    arg = parse_expression(ps)

    return EXPR{Global}(Any[kw, arg])
end

function parse_local(ps::ParseState)
    kw = KEYWORD(ps)
    arg = parse_expression(ps)

    return EXPR{Local}(Any[kw, arg])
end

function parse_return(ps::ParseState)
    kw = KEYWORD(ps)
    args = closer(ps) ? NOTHING : parse_expression(ps)

    return EXPR{Return}(Any[kw, args])
end


# One line

@addctx :abstract function parse_abstract(ps::ParseState)
    # Switch for v0.6 compatability
    if ps.nt.kind == Tokens.TYPE
        kw1 = KEYWORD(ps)
        kw2 = KEYWORD(next(ps))
        sig = @closer ps block parse_expression(ps)
        ret = EXPR{Abstract}(Any[kw1, kw2, sig, accept_end(ps)])
    else
        kw = KEYWORD(ps)
        sig = parse_expression(ps)
        ret = EXPR{Abstract}(Any[kw, sig])
    end
    return ret
end

@addctx :primitive function parse_primitive(ps::ParseState)
    if ps.nt.kind == Tokens.TYPE
        kw1 = KEYWORD(ps)
        kw2 = KEYWORD(next(ps))
        sig = @closer ps ws @closer ps wsop parse_expression(ps)
        arg = @closer ps block parse_expression(ps)

        ret = EXPR{Primitive}(Any[kw1, kw2, sig, arg, accept_end(ps)])
    else
        ret = IDENTIFIER(ps)
    end
    return ret
end

function parse_imports(ps::ParseState)
    kw = KEYWORD(ps)
    kwt = is_import(kw) ? Import :
          is_importall(kw) ? ImportAll :
          Using
    tk = ps.t.kind

    arg = parse_dot_mod(ps)

    if ps.nt.kind != Tokens.COMMA && ps.nt.kind != Tokens.COLON
        ret = EXPR{kwt}(vcat(kw, arg))
    elseif ps.nt.kind == Tokens.COLON
        ret = EXPR{kwt}(vcat(kw, arg))
        push!(ret, OPERATOR(next(ps)))

        arg = parse_dot_mod(ps, true)
        append!(ret, arg)
        while ps.nt.kind == Tokens.COMMA
            accept_comma(ps, ret)
            arg = parse_dot_mod(ps, true)
            append!(ret, arg)
        end
    else
        ret = EXPR{kwt}(vcat(kw, arg))
        while ps.nt.kind == Tokens.COMMA
            accept_comma(ps, ret)
            arg = parse_dot_mod(ps)
            append!(ret, arg)
        end
    end

    return ret
end

function parse_export(ps::ParseState)
    args = Any[KEYWORD(ps)]
    append!(args, parse_dot_mod(ps))

    while ps.nt.kind == Tokens.COMMA
        push!(args, PUNCTUATION(next(ps)))
        arg = parse_dot_mod(ps)[1]
        push!(args, arg)
    end

    return EXPR{Export}(args)
end


# Block

@addctx :begin function parse_begin(ps::ParseState)
    kw = KEYWORD(ps)
    blockargs = parse_block(ps, Any[], (Tokens.END,), true)
    return EXPR{Begin}(Any[kw, EXPR{Block}(blockargs), accept_end(ps)])
end

@addctx :quote function parse_quote(ps::ParseState)
    kw = KEYWORD(ps)
    blockargs = parse_block(ps)
    return EXPR{Quote}(Any[kw, EXPR{Block}(blockargs), accept_end(ps)])
end

@addctx :function function parse_function(ps::ParseState)
    kw = KEYWORD(ps)
    offset = ps.nt.startbyte
    sig = @closer ps inwhere @closer ps ws parse_expression(ps)

    if sig isa EXPR{InvisBrackets} && !(sig.args[2] isa EXPR{TupleH})
        istuple = true
        sig = EXPR{TupleH}(sig.args)
    elseif sig isa EXPR{TupleH}
        istuple = true
    else
        istuple = false
    end
    if sig isa EXPR
        offset += sig.args[1].fullspan
        for i = 2:length(sig.args)
            if !(sig.args[i] isa PUNCTUATION)
                @addbinding ps sig.args[i]
            end
            offset += sig.args[i].fullspan
        end
    end

    while ps.nt.kind == Tokens.WHERE && ps.ws.kind != Tokens.NEWLINE_WS
        sig = @closer ps inwhere @closer ps ws parse_compound(ps, sig)
    end
    
    blockargs = parse_block(ps)

    if isempty(blockargs)
        if sig isa EXPR{Call} || sig isa WhereOpCall || (sig isa BinarySyntaxOpCall && !(is_exor(sig.arg1))) || istuple
            args = Any[sig, EXPR{Block}(blockargs)]
        else
            args = Any[sig]
        end
    else
        args = Any[sig, EXPR{Block}(blockargs)]
    end

    ret = EXPR{FunctionDef}(Any[kw])
    for a in args
        push!(ret, a)
    end
    accept_end(ps, ret)
    return ret
end

@addctx :macro function parse_macro(ps::ParseState)
    kw = KEYWORD(ps)
    sig = @closer ps ws parse_expression(ps)
    blockargs = parse_block(ps)

    return EXPR{Macro}(Any[kw, sig, EXPR{Block}(blockargs), accept_end(ps)])
end

# loops
@addctx :for function parse_for(ps::ParseState)
    kw = KEYWORD(ps)
    ranges = parse_ranges(ps)
    blockargs = parse_block(ps)

    return EXPR{For}(Any[kw, ranges, EXPR{Block}(blockargs), accept_end(ps)])
end

@addctx :while function parse_while(ps::ParseState)
    kw = KEYWORD(ps)
    cond = @closer ps ws parse_expression(ps)
    blockargs = parse_block(ps)

    return EXPR{While}(Any[kw, cond, EXPR{Block}(blockargs), accept_end(ps)])
end

# control flow

"""
    parse_if(ps, ret, nested=false, puncs=[])

Parse an `if` block.
"""
@addctx :if function parse_if(ps::ParseState, nested = false)
    # Parsing
    kw = KEYWORD(ps)
    if ps.ws.kind == NewLineWS || ps.ws.kind == SemiColonWS
        push!(ps.errors, Error((ps.ws.startbyte:ps.ws.endbyte) .+ 1 , "Missing conditional in if statement."))
        cond = ErrorToken()
    else
        cond = @closer ps ws parse_expression(ps)
    end
    ifblockargs = parse_block(ps, Any[], (Tokens.END, Tokens.ELSE, Tokens.ELSEIF))

    if nested
        ret = EXPR{If}(Any[cond, EXPR{Block}(ifblockargs)])
    else
        ret = EXPR{If}(Any[kw, cond, EXPR{Block}(ifblockargs)])
    end

    elseblockargs = Any[]
    if ps.nt.kind == Tokens.ELSEIF
        push!(ret, KEYWORD(next(ps)))
        push!(elseblockargs, parse_if(ps, true))
    end
    elsekw = ps.nt.kind == Tokens.ELSE
    if ps.nt.kind == Tokens.ELSE
        push!(ret, KEYWORD(next(ps)))
        parse_block(ps, elseblockargs)
    end

    # Construction
    if !(isempty(elseblockargs) && !elsekw)
        push!(ret, EXPR{Block}(elseblockargs))
    end
    !nested && accept_end(ps, ret)

    return ret
end

@addctx :let function parse_let(ps::ParseState)
    args = Any[KEYWORD(ps)]
    if !(ps.ws.kind == NewLineWS || ps.ws.kind == SemiColonWS)
        arg = @closer ps range @closer ps ws  parse_expression(ps)
        if ps.nt.kind == Tokens.COMMA
            arg = EXPR{Block}(Any[arg])
            while ps.nt.kind == Tokens.COMMA
                accept_comma(ps, arg)
                startbyte = ps.nt.startbyte
                nextarg = @closer ps comma @closer ps ws parse_expression(ps)
                push!(arg, nextarg)
            end
        end
        push!(args, arg)
    end
    
    blockargs = parse_block(ps)
    push!(args, EXPR{Block}(blockargs))
    accept_end(ps, args)

    return EXPR{Let}(args)
end

@addctx :try function parse_try(ps::ParseState)
    kw = KEYWORD(ps)
    ret = EXPR{Try}(Any[kw])

    tryblockargs = parse_block(ps, Any[], (Tokens.END, Tokens.CATCH, Tokens.FINALLY))
    push!(ret, EXPR{Block}(tryblockargs))

    #  catch block
    if ps.nt.kind == Tokens.CATCH
        next(ps)
        push!(ret, KEYWORD(ps))
        # catch closing early
        if ps.nt.kind == Tokens.FINALLY || ps.nt.kind == Tokens.END
            caught = FALSE
            catchblock = EXPR{Block}(Any[])
        else
            if ps.ws.kind == SemiColonWS || ps.ws.kind == NewLineWS
                caught = FALSE
            else
                caught = @closer ps ws parse_expression(ps)
            end
            
            catchblockargs = parse_block(ps, Any[], (Tokens.END, Tokens.FINALLY))
            if !(caught isa IDENTIFIER || caught == FALSE)
                pushfirst!(catchblockargs, caught)
                caught = FALSE
            end
            catchblock = EXPR{Block}(catchblockargs)
        end
    else
        caught = FALSE
        catchblock = EXPR{Block}(Any[])
    end
    push!(ret, caught)
    push!(ret, catchblock)

    # finally block
    if ps.nt.kind == Tokens.FINALLY
        if isempty(catchblock.args)
            ret.args[4] = FALSE
        end
        push!(ret, KEYWORD(next(ps)))
        finallyblockargs = parse_block(ps)
        push!(ret, EXPR{Block}(finallyblockargs))
    end

    push!(ret, accept_end(ps))
    return ret
end

@addctx :do function parse_do(ps::ParseState, @nospecialize(ret))
    kw = KEYWORD(next(ps))

    args = EXPR{TupleH}(Any[])
    @closer ps comma @closer ps block while !closer(ps)
        a = @addbinding ps parse_expression(ps)
        push!(args, a)
        if ps.nt.kind == Tokens.COMMA
            accept_comma(ps, args)
        end
    end

    blockargs = parse_block(ps)

    return EXPR{Do}(Any[ret, kw, args, EXPR{Block}(blockargs), accept_end(ps)])
end

# modules

@addctx :module function parse_module(ps::ParseState)
    kw = KEYWORD(ps)
    @assert kw.kind == Tokens.MODULE || kw.kind == Tokens.BAREMODULE # work around julia issue #23766
    if ps.nt.kind == Tokens.IDENTIFIER
        arg = IDENTIFIER(next(ps))
    else
        arg = @precedence ps 15 @closer ps ws parse_expression(ps)
    end

    blockargs = parse_block(ps, Any[], (Tokens.END,), true)
    block = EXPR{Block}(blockargs)

    return EXPR{(is_module(kw) ? ModuleH : BareModule)}(Any[kw, arg, block, accept_end(ps)])
end


function parse_mutable(ps::ParseState)
    if ps.nt.kind == Tokens.STRUCT
        kw = KEYWORD(ps)
        next(ps)
        ret = parse_struct(ps, true)
        pushfirst!(ret, kw)
        update_span!(ret)
    else
        ret = IDENTIFIER(ps)
    end
    return ret
end


@addctx :struct function parse_struct(ps::ParseState, mutable)
    kw = KEYWORD(ps)
    sig = @closer ps ws parse_expression(ps)    
    blockargs = parse_block(ps)
    
    return EXPR{mutable ? Mutable : Struct}(Any[kw, sig, EXPR{Block}(blockargs), accept_end(ps)])
end
