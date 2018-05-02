
defmodule Serv do
  require Logger

  @doc """
  Starts accepting connections on the given 'port'.
  """
  def accept(port) do
    # http://erlang.org/doc/man/gen_tcp.html
    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true])

    # Starting Data handler
    {:ok, _} = Task.Supervisor.start_child(Serv.TaskSupervisor, fn -> Memo.start() end)

    Logger.info("Accepting connections on port #{port}")
    loop_acceptor(socket)
  end

  # Lyssnar efter anrop till port och startar process för behandling av input
  defp loop_acceptor(socket) do
    # Vänntar på anslutning
    {:ok, client} = :gen_tcp.accept(socket)

    # Startar process för att behandla anslutning
    {:ok, pid} = Task.Supervisor.start_child(Serv.TaskSupervisor, fn -> serve(client) end)
    :ok = :gen_tcp.controlling_process(client, pid)

    # Loopar funktionen
    loop_acceptor(socket)
  end

  """
  läser från klient och skickar till parse eller fel till log
  """
  defp serve(socket) do
    case read_line(socket) do
      {:error, error} -> Logger.info("serve: #{error}")
      mess ->
        #parse(mess, socket)
        write_line(mess, socket)
        write_line("\r\n", socket)
        "echoed" |> Logger.info()
        serve(socket)
    end
  end

  @doc """
  Tar in förfrågan och skickarvidare info baserad på denna
  """
  def parse(mess, socket) do
    # Gör lista av sträng
    [h | tail] = String.split(mess, " ")
    case h do
      # Skickar vidare info och startar process om POS request
      "POS" -> spawn fn -> pos_req(tail) end

      # Skickar vidare info och startar process om PUT request
      "PUT" ->
        # PUT requests kan vara av olika typ vanlig och PIC
        case tail do
          ["PIC"|t] ->
            spawn fn -> put_pic_req(t, socket) end

          _ ->
            IO.inspect tail, limit: :infinity
            spawn fn -> Enum.join(tail, " ") |> put_req(socket) end
        end

      # Skickar vidare info och startar process om DEL request
      "DEL" -> spawn fn -> del_req(tail) end

      # Skickar vidare info och startar process om PUT request
      "GET" -> spawn fn -> get_req(tail) end
    end
  end

  # Ta hand om POS requests:
  # ID:userID RID:
  # FROM:userID TO:userID
  # memo_mux tar emot: {:user, {user_id, {:set, self, {:notifs, :set}, data}}}
  # skickar vidare till user_data_handler: {:set, self, {:notifs, :set}, data}
  defp pos_req(str) do
    [h , t] = String.split(str, " ")
    [_ , user_id2] = String.split(t, ":")
    String.split(h, ":")
    |> case do
      ["ID", user_id] -> send :memo_mux, {:user, {user_id, {:create_user, nil}}}
      ["FROM", user_id] -> send :memo_mux, {:user, {user_id, {:set, self(),
      %{:friend_request => %{:from => user_id, :to => user_id2}}, {:notifs, :set}}}}       #The exact moment Cornelis mind borke
    end
    receive do
      {:memo, :ok} -> Logger.info("notif set")
      {:error, error} -> Logger.info(error)
    end
  end

  defp put_pic_req(tail, socket) do
    IO.inspect tail, limit: :infinity

    # send ok
    write_line("ok\r\n", socket)
    Logger.info("ok sent")

    # Get pic
    pic_mess = read_image([], tail |> List.first() |> String.to_integer(), socket)
    Logger.info("got pic")
    Logger.info(Enum.count(pic_mess))

    # send ok
    write_line("ok\r\n", socket)
    Logger.info("ok2 sent")

    # send pic
    pic_mess |> Enum.reverse() # |> send_mess(socket) TODO Byt ut mot spara till memo
    Logger.info("pic sent")
  end

  # Läser in len stor bild i 1024 bytes bitar
  defp read_image(mem, 0, _), do: mem
  defp read_image(mem, len, socket) do
    cond do
      len > 1024 ->
        [read_bytes(socket, 1024) | mem]
        |> read_image(len - 1024, socket)
      # Nedan går endast igång om inget ovan gått igång
      true ->
        Logger.info(len)
        [read_bytes(socket, len) | mem]
        |> read_image(0, socket)
    end
  end

  # Echoserver:
  defp put_req(json, socket) do
    #IO.inspect json
    write_line("#{json}\r\n\r\n", socket)
    Logger.info("Sent mess")
  end

# TODO
# Tar hand om put requests som ser ut som följande:
# ID:user_id RID:thing@userName@roomName | @missionName <JSON>
# Skickar till memo_mux som tar emot: {:room, {room_id, action}}
# Om du lägger till ett quest skickas detta vidare till action roomhandler, som tar emot: {:room, {room_id, action}}
# Om du uppdaterar ett rum/skapar ett rum förväntar sig roomhandler action: {:set, pid, {:room, which_room_part, part_to_add, :how}}
# how = :add eller :del
  defp put_req(str) do
    [id, rid, json] = str |> String.split(" ")
    decoded = Jason.decode!(json)
    [_, user_id] = id |> String.split(":")
    [_, res_id] = rid |> String.split(":")
    String.split(res_id, "@")
    |> case do
      # Room
      [_, _, room_id] ->
        #"Ingen gillar compilation errors"
        #TODO: send :memo_mux * antal rum-attributer, uppdatera alla olika room_parts
        send :memo_mux, {:room, {room_id, {:set, self(), {:room, :owner, decoded |> Map.fetch("owner"), :add}}}}
        send :memo_mux, {:room, {room_id, {:set, self(), {:room, :name, decoded |> Map.fetch("roomName"), :add}}}}
        send :memo_mux, {:room, {room_id, {:set, self(), {:room, :topic, decoded |> Map.fetch("description"), :add}}}}

        # send :memo_mux, {:room, {room_id, {:set, self(), {:room, :members, decoded |> Map.fetch("members"), :add}}}}
        # Not going to work Marcus konvertering: "members" => [%{"im" => 312312414, "userName" => "Amanda N"}, etc... ]
        # Vår users: [{:user, user_id}, etc...]
        # fetch returnerar {:ok, saken} >_>

      # Quest
      [_, _, room_id, quest_id] ->
        send :memo_mux, {:room, {room_id, {:set, self(), {:quest, quest_id, json}}}}
    end
  end

  # TODO
  # Ska ta hand om DEL requests
  defp del_req(_) do end

  # TODO
  # Ska ta hand om GET requests
  defp get_req(_) do end


  # Läser bytes antal bytes från socker-sött
  defp read_bytes(socket, bytes) do
    case :gen_tcp.recv(socket, bytes) do
      {:ok, data} -> data
      {:error, closed} -> {:error, closed}
    end
  end

  # Läser oändligt (not really) långa meddelanden från socket
  defp read_line(socket) do
    case :gen_tcp.recv(socket, 0) do #How this know where to stop is magic.
      {:ok, data} -> data
      {:error, closed} -> {:error, closed}
    end
  end

  # Skickar medelande till socket
  defp write_line(line, socket) do
    case :gen_tcp.send(socket, line) do
      {:error, error} -> {:error, error}
      _ -> :ok
    end
  end

  # TODO InProgress
  # Skickar data från lista till socket
  defp send_mess([], socket), do: write_line("\r\n", socket)
  defp send_mess([h|t], socket) do
    case write_line(h, socket) do
      :ok ->  send_mess(t, socket)
      {:error, error} -> Logger.info("send_mess: #{error}")
    end
  end
end
