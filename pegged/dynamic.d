module pegged.dynamic;

import std.array: join;
import std.conv: to;

import std.stdio;

import pegged.peg;

alias ParseTree delegate(ParseTree) Dynamic;

string getName(T...)(T rules) if (T.length)
{
    string result;
    foreach(i,r; rules)
        result ~= r(ParseTree()).name ~ (i < rules.length -1 ? ", " : "");
    return result;
}

Dynamic fail()
{
    return (ParseTree p)
    {
        return ParseTree("fail", false, ["fail"], p.input, p.end, p.end);
    };
}

Dynamic eoi()
{
    return (ParseTree p)
    {
        if (p.end == p.input.length)
            return ParseTree("eoi", true, [], p.input, p.end, p.end);
        else
            return ParseTree("eoi", false, ["end of input"], p.input, p.end, p.end);
    };
}

Dynamic any()
{
    return(ParseTree p)
    {
        if (p.end < p.input.length)
            return ParseTree("any", true, [p.input[p.end..p.end+1]], p.input, p.end, p.end+1);
        else
            return ParseTree("any", false, ["any char"], p.input, p.end, p.end);
    };
}

Dynamic literal(string s)
{
    return (ParseTree p)
    {
        if (p.end+s.length <= p.input.length && p.input[p.end..p.end+s.length] == s)
            return ParseTree("literal!(\"" ~ s ~ "\")", true, [s], p.input, p.end, p.end+s.length);
        else
            return ParseTree("literal!(\"" ~ s ~ "\")", false, [`"` ~ s ~ `"`], p.input, p.end, p.end);

    };
}

Dynamic charRange(char begin, char end)
{
    return (ParseTree p)
    {
        string longName = "a char between '"~to!string(begin)~"' and '"~to!string(end)~"'";
        if (p.end < p.input.length && p.input[p.end] >= begin && p.input[p.end] <= end)
            return ParseTree("charRange!(" ~ to!string(begin) ~ ", " ~ to!string(end) ~ ")", true, [p.input[p.end..p.end+1]], p.input, p.end, p.end+1);
        else
            return ParseTree("charRange!(" ~ to!string(begin) ~ ", " ~ to!string(end) ~ ")", false, [longName], p.input, p.end, p.end);
    };

}

Dynamic eps()
{
    return (ParseTree p)
    {
        return ParseTree("eps", true, [""], p.input, p.end, p.end);
    };
}

Dynamic wrapAround(Dynamic before, Dynamic middle, Dynamic after)
{
    return(ParseTree p)
    {
        ParseTree temp = before(p);
        if (!temp.successful)
            return temp;

        ParseTree result = middle(temp);
        if (!result.successful)
            return result;
        result.begin = temp.begin;

        temp = after(result);
        if (!temp.successful)
            return temp;

        result.end = temp.end;
        return result;
    };
}

Dynamic zeroOrMore(Dynamic r)
{
    return (ParseTree p)
    {
        //r = literal("b");
        //writeln("Entering *: ", p.input);
        ParseTree result = ParseTree("zeroOrMore!(" ~ getName(r) ~ ")", true, [], p.input, p.end, p.end);
        //writeln("Calling r");
        ParseTree temp = r(result);
        //writeln("result.input: ", result.input, " result.end: ", result.end);
        //writeln("name: ", getName(r));
        //writeln("r(result): ", r(result));
        while(temp.successful
            && (temp.begin < temp.end // To avoid infinite loops on epsilon-matching rules
            || temp.name.startsWith("discard!(")))
        {
            result.matches ~= temp.matches;
            result.children ~= temp;
            result.end = temp.end;
            temp = r(result);
        }
        result.successful = true;
        return result;
    };
}

Dynamic oneOrMore(Dynamic r)
{
    return(ParseTree p)
    {
        auto result = ParseTree("oneOrMore!(" ~ getName(r) ~ ")", false, [], p.input, p.end, p.end);
        auto temp = r(result);

        if (!temp.successful)
        {
            result.matches = temp.matches;
            result.children = [temp];
            result.end = temp.end;
        }
        else
        {
            while(  temp.successful
                && (temp.begin < temp.end // To avoid infinite loops on epsilon-matching rules
            || temp.name.startsWith("discard!(")))
            {
                result.matches ~= temp.matches;
                result.children ~= temp;
                result.end = temp.end;
                temp = r(result);
            }
            result.successful = true;
        }
        return result;
    };
}

Dynamic option(Dynamic r)
{
    return (ParseTree p)
    {
        ParseTree result = r(p);
        if (result.successful)
            return ParseTree("option!(" ~ getName(r) ~ ")", true, result.matches, result.input, result.begin, result.end, [result]);
        else
            return ParseTree("option!(" ~ getName(r) ~ ")", true, [], p.input, p.end, p.end, null);
    };
}

Dynamic and(T...)(T rules)
{
    return (ParseTree p)
    {
        bool keepNode(ParseTree node)
        {
            return    node.name.startsWith("keep!(")
                || (  !node.name.startsWith("discard!(")
                   //&& !node.name.startsWith("drop!(")
                   && node.matches !is null
                   //&& node.begin != node.end
                   );
        }

        ParseTree result = ParseTree("and!(" ~ getName(rules) ~ ")", false, [], p.input, p.end, p.end, []);

        foreach(i,r; rules)
        {
            ParseTree temp = r(result);
            result.end = temp.end;
            if (temp.successful)
            {
                if (keepNode(temp))
                {
                    result.matches ~= temp.matches;
                    if (temp.name.startsWith("drop!("))
                    {}
                    else if (temp.name.startsWith("propagate!("))
                        result.children ~= temp.children;
                    else
                        result.children ~= temp;
                }
            }
            else
            {
                result.children ~= temp;// add the failed node, to indicate which failed
                if (temp.matches.length > 0)
                    result.matches ~= temp.matches[$-1];
                return result; // and end the parsing attempt right there
            }
        }
        result.successful = true;
        return result;
    };
}

Dynamic or(T...)(T rules)
{
    return (ParseTree p)
    {
        // error-management
        ParseTree longestFail = ParseTree("or!(" ~ getName(rules) ~ ")", false, [], p.input, p.end, 0);
        string[] errorStrings;
        size_t errorStringChars;
        string orErrorString;

        ParseTree[] results;
        string[] names;
        size_t[] failedLength;
        size_t maxFailedLength;

        // Real 'or' loop
        foreach(i,r; rules)
        {
            ParseTree temp = r(p);
            if (temp.successful)
            {
                temp.children = [temp];
                temp.name = "or!(" ~ getName(rules) ~ ")";
                return temp;
            }
            else
            {
                string errName = " (" ~ getName(r) ~ ")";
                failedLength ~= temp.end;
                if (temp.end >= longestFail.end)
                {
                    maxFailedLength = temp.end;
                    longestFail = temp;
                    names ~= errName;
                    results ~= temp;

                    if (temp.end == longestFail.end)
                        errorStringChars += temp.matches[$-1].length + errName.length + 4;
                    else
                        errorStringChars = temp.matches[$-1].length + errName.length + 4;
                }
                // Else, this error parsed less input than another one: we discard it.
            }
        }

        // All subrules failed, we will take the longest match as the result
        // If more than one node failed at the same (farthest) position, we concatenate their error messages

        char[] errString;// = new char[](errorStringChars);
        errString.length = errorStringChars;
        uint start = 0;
        foreach(i; 0..rules.length)
        {
            if (failedLength[i] == maxFailedLength)
            {
                auto temp = results[i];
                auto len = temp.matches[$-1].length;
                auto nlen = names[i].length;
                errString[start .. start+len] = temp.matches[$-1];
                errString[start+len .. start+len+names[i].length] = names[i];
                errString[start+len+nlen .. start+len+nlen+4] = " or ";
                start += len + names[i].length + 4;
            }
        }
        orErrorString = cast(string)(errString[0..$-4]);

        longestFail.matches = longestFail.matches[0..$-1]  // discarding longestFail error message
                            ~ [orErrorString];             // and replacing it by the new, concatenated one.
        longestFail.name = "or!(" ~ getName(rules) ~ ")";
        longestFail.begin = p.end;
        return longestFail;
    };
}

Dynamic posLookahead(Dynamic r)
{
    return (ParseTree p)
    {
        ParseTree temp = r(p);
        if (temp.successful)
            return ParseTree("posLookahead!(" ~ getName(r) ~ ")", temp.successful, [], p.input, p.end, p.end);
        else
            return ParseTree("posLookahead!(" ~ getName(r) ~ ")", temp.successful, [temp.matches[$-1]], p.input, p.end, p.end);
    };
}

Dynamic negLookahead(Dynamic r)
{
    return (ParseTree p)
    {
        ParseTree temp = r(p);
        if (temp.successful)
            return ParseTree("negLookahead!(" ~ getName(r) ~ ")", false, ["anything but \"" ~ p.input[temp.begin..temp.end] ~ "\""], p.input, p.end, p.end);
        else
            return ParseTree("negLookahead!(" ~ getName(r) ~ ")", true, [], p.input, p.end, p.end);
    };
}

Dynamic named(Dynamic r, string name)
{
    return (ParseTree p)
    {
        ParseTree result = r(p);
        result.name = name;
        return result;
    };
}

Dynamic action(Dynamic r, Dynamic act)
{
    return (ParseTree p)
    {
        return act(r(p));
    };
}

Dynamic fuse(Dynamic r)
{
    return(ParseTree p)
    {
        p = r(p);
        if (p.successful)
        {
            if (p.matches.length != 0)
                p.matches = [std.array.join(p.matches)];

            p.children = null; // also discard children
        }
        return p;
    };
}

Dynamic discardChildren(Dynamic r)
{
    return (ParseTree p)
    {
        p = r(p);
        p.children = null;
        return p;
    };
}

Dynamic discardMatches(Dynamic r)
{
    return (ParseTree p)
    {
        p = r(p);
        if (p.successful)
            p.matches = null;
        return p;
    };
}

Dynamic discard(Dynamic r)
{
    return (ParseTree p)
    {
        ParseTree result = r(p);
        result.name = "discard!(" ~ getName(r) ~ ")";
        //result.begin = result.end;
        result.children = null;
        if (result.successful)
            result.matches = null;//to keep error messages, if any

        return result;
    };
}

Dynamic drop(Dynamic r)
{
    return (ParseTree p)
    {
        ParseTree result = r(p);
        result.children = null;
        if (result.successful)
            result.name = "drop!(" ~ getName(r) ~ ")";
        return result;
    };
}

Dynamic propagate(Dynamic r)
{
    return (ParseTree p)
    {
        ParseTree result = r(p);
        if (result.successful)
            result.name = "propagate!(" ~ getName(r) ~ ")";
        return result;
    };
}

Dynamic keep(Dynamic r)
{
    return (ParseTree p)
    {
        ParseTree result = r(p);
        if (result.successful)
        {
            result.children = [result];
            result.name = "keep!(" ~ getName(r) ~ ")";
        }
        return result;
    };
}
