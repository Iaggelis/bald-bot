# based on the irc part of DonHo's bot
# https://github.com/DonHonerbrink/bruhbot
module IRC

module Utils
include("tcp.jl")
include("mcmc.jl")

using .tcp
using .mcmc

using Sockets, Printf, SQLite, Tables, Serialization

# exports
export irc_connect, irc_send, read_oauth_file, irc_auth, irc_join,
    irc_readlines

function irc_connect(tcp_sock::TCPSocket, config)
    tcp_create_sock(tcp_sock)
    tcp_connect(tcp_sock, config.hostname, config.port)
    return Status(tcp_sock.status)
end

function irc_send(tcp_sock::TCPSocket, buffer::String)
    buffer = buffer * '\r' * '\n'
    # @printf(stdout, "< %s", buffer)
    tcp_send(tcp_sock, buffer)
end

function irc_send(tcp_sock::TCPSocket, channel::String, buffer::Vararg{String})
    start_buffer = @sprintf("PRIVMSG #%s :", channel)
    # buffer = start_buffer * buffer * '\r' * '\n'
    buffer = start_buffer * foldr(*, buffer)
    buffer *= '\r' * '\n'
    @printf(stdout, "< %s", buffer)
    tcp_send(tcp_sock, buffer)
end

function read_oauth_file(filename::String)
    oauth = ""
    open(filename, "r") do file
        line = readline(file)
        oauth = line
    end
    return oauth
end

function irc_auth(tcp_sock::TCPSocket, nick::String, oauth::String)
    buffer = ""
    buffer = @sprintf("PASS %s\r\n", oauth)
    irc_send(tcp_sock, buffer)

    buffer = @sprintf("NICK %s\r\n", nick)
    irc_send(tcp_sock, buffer)

end

function irc_join(tcp_sock::TCPSocket, channel::String)
    buffer = ""
    buffer = @sprintf("JOIN #%s\r\n", channel)
    irc_send(tcp_sock, buffer)
end

function irc_readlines(tcp_sock::TCPSocket, config)
    load_cmds()
    buffer = ""
    begin
        while !eof(tcp_sock)
            line = readline(tcp_sock)
            println(stdout,"> ", line)
            if line != nothing
                irc_parse_msg(tcp_sock, line, config)
            end
        end
    end

    return Status(tcp_sock.status), buffer
end

function irc_parse_msg(tcp_sock::TCPSocket, line::String, config)
    if line == "PING :tmi.twitch.tv"
        irc_send(tcp_sock, "PONG :tmi.twitch.tv")
    end
    m = match(r":(?<sender>.*)!.*#(?<channel>\w+) :(?<msg>.*)", line)
    if m !== nothing
        sender = String(m[:sender])
        channel = String(m[:channel])
        msg = String(m[:msg])

        process_commands(tcp_sock, channel, msg, sender=sender,
                         preffix=config.cmd_preffix)
        @async log_msg(channel, sender, msg)
    end
end

function process_commands(tcp_sock::TCPSocket, chn::String, msg::String;
                          sender::String="", preffix::String="")
    cmd_regex = Regex("^" * preffix * "(?<cmd>\\w+) ?(?<body>.*)")
    command = match(cmd_regex, msg)
    if command != nothing
        if command[:cmd] == "ping"
            irc_send(tcp_sock, chn, "PONG")
        elseif command[:cmd] == "pog"
            irc_send(tcp_sock, chn, "@$sender Pogey")
        elseif command[:cmd] == "markov"
            irc_send(tcp_sock, chn, markov())
        elseif command[:cmd] == "addcmd"
            defineCMD(tcp_sock, chn, String(command[:body]))
        elseif command[:cmd] == "commands"
            irc_send(tcp_sock, chn,
                     Iterators.flatten(collect(keys(defined_cmds))))
        elseif command[:cmd] in keys(defined_cmds)
            index = command[:cmd]
            defined_cmds[index][1](tcp_sock, chn, defined_cmds[index][2])
        end
    end

end

function log_msg(chn::String, sender::String, msg::String)
    msg = replace(msg, "\""=>"")
    filename = "twitch_log.db"
    db = SQLite.DB()
    db = DBInterface.connect(SQLite.DB, filename)
    execute_string = @sprintf "CREATE TABLE IF NOT EXISTS %s (
                             sender TEXT,
                             msg TEXT)" chn
    DBInterface.execute(db, execute_string)
    prepare_string = @sprintf "INSERT INTO %s VALUES(?,?)" chn
    q = DBInterface.prepare(db, prepare_string)
    SQLite.execute(q, (sender,msg))
    DBInterface.close!(db)


end

function markov()
    logfile::String = "twitch_log.db"
    buffer = ""
    db = SQLite.DB(logfile)
    cols = DBInterface.execute(db,"""SELECT * FROM john_pft
                                    WHERE msg NOT LIKE '!%' """
                               ) |> columntable
    foreach(x-> buffer *= x * " " , cols[2])
    gen_text = mcmc.generate_from_string(buffer)
    return gen_text
end

const cmd = Dict("say"=> irc_send, "test"=> println)

const defined_cmds = Dict{String, Tuple{Function, String}}()


#TODO: this would be better alone in a module
# command functionality
function defineCMD(tcp_sock, chn, expression::String)
    m = match(r"%(?<cmdName>\w+) %(?<func>\w+)*\((?<body>.*)\)", expression)
    if m[:cmdName] in keys(cmd)
        defined_cmds[m[:cmdName]] = (cmd[m[:func]], String(m[:body]))
        open("commands_test.bin", "w") do f
            serialize(f, defined_cmds)
        end
    end

end

function generate()
    for (key, command) in cmd
        eval(quote
             $(Symbol(key))(sock, chn::String) = $command(sock, chn, "hello")
             end)
    end
end

function load_cmds()
    #TODO check if files exists
    cmds_dump = "commands_test.bin"
    if isfile(cmds_dump)
        merge!(defined_cmds, deserialize(cmds_dump))
    end
end

end # irc_Utils



# end # Commands

end # IRC
