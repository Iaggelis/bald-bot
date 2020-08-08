module irc
include("tcp.jl")
include("mcmc.jl")

using .tcp
using .mcmc

using Sockets, Printf

# exports
export irc_connect, irc_send, read_oauth_file, irc_auth, irc_join,
    irc_readlines


function irc_connect(tcp_sock::TCPSocket, hostname, port)
    tcp_create_sock(tcp_sock)
    tcp_connect(tcp_sock, hostname, port)
    return Status(tcp_sock.status)
end

function irc_send(tcp_sock::TCPSocket, buffer::String)
    buffer = buffer * '\r' * '\n'
    # @printf(stdout, "< %s", buffer)
    tcp_send(tcp_sock, buffer)
end

function irc_send(tcp_sock::TCPSocket, channel::String, buffer::String)
    start_buffer = @sprintf("PRIVMSG #%s :", channel)
    buffer = start_buffer * buffer * '\r' * '\n'
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

function irc_readlines(tcp_sock::TCPSocket)
    buffer = ""
    begin
        while !eof(tcp_sock)
            line = readline(tcp_sock)
            println(stdout,"> ", line)
            if line != nothing
                irc_parse_msg(tcp_sock, line)
            end
        end
    end

    return Status(tcp_sock.status), buffer
end

function irc_parse_msg(tcp_sock::TCPSocket, line::String)
    if line == "PING :tmi.twitch.tv"
        irc_send(tcp_sock, "PONG :tmi.twitch.tv")
    end
    m = match(r":(.*)!.*#(.*) :(.*)", line)
    if m !== nothing
        sender = String(m.captures[1])
        channel = String(m.captures[2])
        msg = String(m.captures[3])

        log_msg(channel, sender, msg)
        if msg[1] == '!' && channel == "john_pft"
            process_commands(tcp_sock, channel, msg, sender=sender)
        end
    end
end

function process_commands(tcp_sock::TCPSocket, chn::String, msg::String;
                          sender::String="")
    command = match(r"!(.*)", msg)
    if command[1] == "ping"
        irc_send(tcp_sock, "john_pft", "PONG")
    elseif command[1] == "pog"
        irc_send(tcp_sock, chn, "@$sender Pogey")
    elseif command[1] == "markov"
        irc_send(tcp_sock, "john_pft", markov())
    end

end

function log_msg(chn::String, sender::String, msg::String)
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
    cols = DBInterface.execute(db,"SELECT * FROM john_pft") |> columntable
    foreach(x-> buffer *= x * " " , cols[2])
    gen_text = mcmc.generate_from_string(buffer)
    return gen_text
end

end # module
