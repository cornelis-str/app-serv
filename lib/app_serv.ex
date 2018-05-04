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
    # Väntar på anslutning
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
        parse(mess, socket)
        write_line(mess, socket)
        write_line("\r\n", socket)
        "echoed" |> Logger.info()
        serve(socket)
    end
  end

  @doc """
  Tar in förfrågan och skickar vidare info baserad på denna
  """
  def parse(mess, socket) do
    # Gör lista av sträng
    [h | tail] = String.split(mess, " ")
    case h do
      # Skickar vidare info och startar process om POS request
      "POS" -> spawn fn -> pos_req(tail, socket) end

      # Skickar vidare info och startar process om PUT request
      "PUT" ->
        # PUT requests kan vara av olika typ vanlig och PIC
        case tail do
          ["PIC"|t] ->
            spawn fn -> put_pic_req(t, socket) end

          _ ->
            IO.inspect tail, limit: :infinity
            spawn fn -> put_req(tail, socket) end
        end

      # Skickar vidare info och startar process om DEL request
      "DEL" -> spawn fn -> del_req(tail, socket) end

      # Skickar vidare info och startar process om PUT request
      "GET" -> spawn fn -> get_req(tail, socket) end
    end
  end

  # Ta hand om POS requests:
  # ID:userID RID:
  # FROM:userID TO:userID +- ROOM:roomID +- QUEST:questID <string> eller en bild som skickas senare
  # memo_mux tar emot: {:user, {user_id, {:set, self, {:notifs, :set}, data}}}
  # skickar vidare till user_data_handler: {:set, self, {:notifs, :set}, data}
  defp pos_req(str, socket) do
    [h | _] = String.split(str, " ")
    String.split(h, ":")
    |> case do
      ["ID", user_id] ->
        send :memo_mux, {:user, user_id, {:create_user, %{:user_id => user_id, :notifs =>[], :friends => [], :rooms => []}}}
        receive do
          {:memo, :ok} ->
            write_line("201\r\n", socket)
          {:error, error} ->
            Logger.info(error)
        end
      ["FROM", user_id] ->
        str |> String.split(" ")
        |> case do
          [_, to] ->
            [_, user_id2] = to |> String.split(":")
            send :memo_mux, {:user, user_id, {:set, self(), {:notifs, %{:friend_request => %{:from => user_id, :to => user_id2}}, :set}}}       #The exact moment Cornelis mind borke
            send :memo_mux, {:user, user_id2, {:set, self(), {:notifs, %{:friend_request => %{:from => user_id, :to => user_id2}}, :set}}}
            write_line("201\r\n", socket)
          [_, to, third | string] ->
            [_, user_id2] = to |> String.split(":")
            third |> String.split(":")
            |> case do
              ["ROOM", room_id] ->
                pos_req_room(user_id, user_id2, room_id, socket)
              ["QUEST", quest_id]->
                pos_req_quest(user_id, user_id2, quest_id, string, socket)
            end
        end
    end
  end

  defp pos_req_room(user_id, user_id2, room_id, socket) do
    send :memo_mux, {:user, user_id, {:set, self(), {:notifs, %{:group_request => %{:from => user_id, :to => user_id2, :group => room_id}}, :set}}}
    send :memo_mux, {:user, user_id2, {:set, self(), {:notifs, %{:group_request => %{:from => user_id, :to => user_id2, :group => room_id}}, :set}}}
    case all_oks(2) do
      :ok ->
        write_line("201\r\n", socket)
      error ->
        Logger.info(error)
    end
  end

  defp pos_req_quest(user_id, user_id2, quest_id, string, socket) do
    send :memo_mux, {:user, user_id, {:set, self(), {:notifs,
    %{:submitted => %{:from => user_id, :to => user_id2, :quest_id => quest_id}, :pic => nil, :string => string},
    :set}}}
    send :memo_mux, {:user, user_id2, {:set, self(), {:notifs,
    %{:submitted => %{:from => user_id, :to => user_id2, :quest_id => quest_id}, :pic => nil, :string => string},
    :set}}}
    case all_oks(2) do
      :ok ->
        write_line("201\r\n", socket)
      error ->
        Logger.info(error)
    end
  end

  # <picID> <byte_len> + <byte[]>
  defp put_pic_req(str, socket) do
    #IO.inspect tail, limit: :infinity
    [pic_id, len] = str |> String.split(" ")

    # send ok
    write_line("ok\r\n", socket)
    Logger.info("ok sent")

    # Get pic
    pic_mess = read_image([], len |> List.first() |> String.to_integer(), socket)
    Logger.info("got pic")
    Logger.info(Enum.count(pic_mess))

    # send ok
    write_line("ok\r\n", socket)
    Logger.info("ok2 sent")

    # save
    pic_mess |> Enum.reverse()
    |> save_pic(pic_id)
  end

  # picID = IMAG@userName@roomName | @missionOwner@missionName@misisonPart@thingName
  # picID = SUBM@userName@roomName@missionOwner@missionName
  # TODO:
  defp save_pic(pic, pic_id) do
    pic_id |> String.split("@")
    |> case do
      ["IMAG", owner_id, room_id] ->
        # Spara rumbild
        "stuff"
      ["IMAG", owner_id, room_id, quest_owner, quest_id, quest_part_id] ->
        # Spara questbilder
        "stuffier"
      ["SUBM", owner_id, room_id, quest_owner, quest_id] ->
        # Submitted quest-pictures
        "stuffiest"
    end
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

# Tar hand om put requests som ser ut som följande:
# ID:user_id RID:thing@userName@roomName | @missionName <JSON>
# Skickar till memo_mux som tar emot: {:room, {room_id, action}}
# Om du lägger till ett quest skickas detta vidare till action roomhandler, som tar emot: {:room, {room_id, action}}
# Om du uppdaterar ett rum/skapar ett rum förväntar sig roomhandler action: {:set, pid, {:room, which_room_part, part_to_add, :how}}
# how = :add eller :del
# thing@userName@roomName@ | missionOwner@missionName | @misisonPart | @thingName
  defp put_req(str, socket) do
    [id, rid | _] = str |> String.split(" ")
    {_, json} = str |> String.split_at(String.length(id) + String.length(rid) + 2)
    decoded = Jason.decode!(json)
    #[_, user_id] = id |> String.split(":")
    [_, res_id] = rid |> String.split(":")
    String.split(res_id, "@")
    |> case do
      # Room
      [_, owner_id, room_id] ->
        {:ok, owner} = decoded |> Map.fetch("owner")
        send :memo_mux, {:room, "#{owner_id}@#{room_id}", {:set, self(), {:room, :owner, owner, :add}}}

        {:ok, room_name} = decoded |> Map.fetch("roomName")
        send :memo_mux, {:room, "#{owner_id}@#{room_id}", {:set, self(), {:room, :name, room_name, :add}}}

        {:ok, desc} = decoded |> Map.fetch("description")
        send :memo_mux, {:room, "#{owner_id}@#{room_id}", {:set, self(), {:room, :topic, desc, :add}}}

        # TODO: lägg till FÖRFRÅGNINGAR, inte lägg till direkt som members i rum.
        members = member_parser(decoded |> Map.fetch("members"), [])
        send :memo_mux, {:room, "#{owner_id}@#{room_id}", {:set, self(), {:room, :members, members, :add}}}

        case all_oks(4) do
          :ok ->
            write_line("201\r\n", socket)
          error ->
            Logger.info(error)
        end

      # Quest
      [_, owner_id, room_id, mission_owner, mission_id] ->
        send :memo_mux, {:room, "#{owner_id}@#{room_id}", {:set, self(), {:quest, "#{owner_id}@#{room_id}@#{mission_owner}@#{mission_id}", json}}}
        receive do
          {:memo, :ok} ->
            write_line("201\r\n", socket)
          {:error, error} ->
            Logger.info(error)
        end
    end
  end

  defp member_parser([], ret), do: ret
  defp member_parser([map | rest], sofar) do
    {:ok, user_id} = map |> Map.fetch("userName")
    member_parser(rest, [{:user, user_id} | sofar])
  end

  defp all_oks(0), do: :ok
  defp all_oks(int) do
    receive do
      {:error, error} -> error
      {:memo, :ok} -> all_oks(int-1)
    end
  end

  # "ID:userID RID:resourceID"
  # "FROM:userID TO:userID +- GROUP:groupID +- QUEST:questID"
  defp del_req(str, socket) do
    str |> String.split(":")
    |> case do
      ["ID" | _] ->
        del_room_quest(str, socket)
      ["FROM" | _] ->
        del_notifs(str, socket)
    end
  end

  # "FROM:userID TO:userID +- GROUP:groupID +- QUEST:questID +- string"
  # Skickar till memo_mux: {:user, user_id, action}
  # action skickas till set notifs: {:set, pid, value, {:notifs, how}}
  defp del_notifs(str, socket) do
    str |> String.split(" ")
    |> case do
      [userID, userID2] ->
        [_, user_id] = userID |> String.split(":")
        [_, user_id2] = userID2 |> String.split(":")
        send :memo_mux, {:user, user_id, {:set, self(), {:notifs, %{:friend_request => %{:from => user_id, :to => user_id2}}, :del}}}
        send :memo_mux, {:user, user_id2, {:set, self(), {:notifs, %{:friend_request => %{:from => user_id, :to => user_id2}}, :del}}}
        case all_oks(2) do
          :ok ->
            write_line("201\r\n", socket)
          error ->
            Logger.info(error)
        end
      [userID, userID2, third] ->
        [_, user_id] = userID |> String.split(":")
        [_, user_id2] = userID2 |> String.split(":")
        third |> String.split(":")
        |> case do
          ["GROUP", room_id] ->
            send :memo_mux, {:user, user_id, {:set, self(), {:notifs, %{:group_request => %{:from => user_id, :to => user_id2, :group => room_id}}, :del}}}
            send :memo_mux, {:user, user_id2, {:set, self(), {:notifs, %{:group_request => %{:from => user_id, :to => user_id2, :group => room_id}}, :del}}}
            case all_oks(2) do
              :ok ->
                write_line("201\r\n", socket)
              error ->
                Logger.info(error)
            end
          ["QUEST", quest_id | string] ->
            send :memo_mux, {:user, user_id, {:set, self(), {:notifs,
            %{:submitted => %{:from => user_id, :to => user_id2, :quest_id => quest_id}, :pic => nil, :string => string},
            :del}}}
            send :memo_mux, {:user, user_id2, {:set, self(), {:notifs,
            %{:submitted => %{:from => user_id, :to => user_id2, :quest_id => quest_id}, :pic => nil, :string => string},
            :del}}}
            case all_oks(2) do
              :ok ->
                write_line("201\r\n", socket)
              error ->
                Logger.info(error)
            end
        end
    end
  end

  # Tar emot:
  # "ID:userID RID:resourceID"
  # Skickar till memo_mux som tar emot: {:room, {room_id, action}}
  # Om du tar bort ett room skickas detta vidare till roomhandler, som tar emot: {:set, pid, {:room, room_id, :del}}
  # Om du tar bort en mission skickas detta vidare till roomhandler, som tar emot: {:set, pid, {:quest, quest_id, quest, how}}
  defp del_room_quest(str, socket) do
    [_, resource_id] = str |> String.split(" ")
    [_, resource_id] = resource_id |> String.split("RID:")
    resource_id |> String.split("@")
    |> case do
      [_, owner_id, room_id] ->
        send :memo_mux, {:room, "#{owner_id}@#{room_id}", {:set, self(), {:room, "#{}@#{room_id}", :del}}}
        receive do
          :ok ->
            write_line("201\r\n", socket)
          error ->
            Logger.info(error)
        end
      [_, owner_id, room_id, mission_owner, mission_id] ->
        send :memo_mux, {:room, "#{owner_id}@#{room_id}", {:set, self(), {:quest, "#{owner_id}@#{room_id}@#{mission_owner}@#{mission_id}", nil, :del}}}
        receive do
          :ok ->
            write_line("201\r\n", socket)
          error ->
            Logger.info(error)
        end
    end
  end


  # Get req
  # ID:userID
  # FROM:userID TO:userID +- GROUP:groupID +- QUEST:questID +- string
  # memo_mux tar emot: {:user, user_id, action = {method, _, _}}
  # skickar vidare action som ska vara: action = {:set, pid, {:friends, user_id, value, how}}
  defp get_req(str, socket) do
    str |> String.split(" ")
    |> case do
      [user] ->
        get_upd(user) |> send_update(socket)
      [from, to] ->
        [_, user_id] = from |> String.split(":")
        [_, user_id2] = to |> String.split(":")

        # lägg till en ny friend på user_id och user_id2
        # plocka ut alla vänner från user_id, bygg denna person som "vän"
        send :memo_mux, {:user, user_id, {:get, self(), {:friends}}}
        receive do
          friends ->
            list1 = parse_friends(friends, [])
        end

        send :memo_mux, {:user, user_id2, {:get, self(), {:friends}}}
        receive do
          friends ->
            list2 = parse_friends(friends, [])
        end

        # add new friends:
        send :memo_mux, {:user, user_id, {:set, self(), {:friends, user_id, {:friend, %{:user_id => user_id2, :friends => list1}}, :add}}}
        send :memo_mux, {:user, user_id2, {:set, self(), {:friends, user_id2, {:friend, %{:user_id => user_id, :friends => list2}}, :add}}}
        # Delete req
        send :memo_mux, {:user, user_id, {:set, self(), {:notifs, %{:friend_request => %{:from => user_id, :to => user_id2}}, :del}}}
        send :memo_mux, {:user, user_id2, {:set, self(), {:notifs, %{:friend_request => %{:from => user_id, :to => user_id2}}, :del}}}

        case all_oks(6) do
          :ok ->
            write_line("201\r\n", socket)
          error ->
            Logger.info(error)
        end

      [from, to, third] ->
        [_, user_id] = from |> String.split(":")
        [_, user_id2] = to |> String.split(":")
        third |> String.split(":")
        |> case do
          ["GROUP", room_id] ->
            IO.puts("not implemented")
            # ta bort grupp/rum förfrågan
            send :memo_mux, {:user, user_id, {:set, self(), {:notifs, %{:group_request => %{:from => user_id, :to => user_id2, :group => room_id}}, :del}}}
            send :memo_mux, {:user, user_id2, {:set, self(), {:notifs, %{:group_request => %{:from => user_id, :to => user_id2, :group => room_id}}, :del}}}
            # Lägg till gruppen i user-data:
            send :memo_mux, {:user, user_id2, {:set, self(), {:rooms, room_id, :add}}}
            # lägg till som member i gruppen (room_data):
            send :memo_mux, {:room, {room_id, {:set, self(), {:room, :users, {:user, user_id2}, :add}}}}

            case all_oks(4) do
              :ok ->
                write_line("201\r\n", socket)
              error ->
                Logger.info(error)
            end

          ["QUEST", quest_id | str] ->
            # TODO: Hur deletear jag notifs utan bilden som jag inte kan ha fått i detta steg eftersom det är så vår kommunikation funkar.
            send :memo_mux, {:user, user_id, {:set, self(), {:notifs, %{:submitted => %{:from => user_id, :to => user_id2, :quest_id => quest_id}, :pic => nil, :string => str}, :del}}}
            send :memo_mux, {:user, user_id2, {:set, self(), {:notifs, %{:submitted => %{:from => user_id, :to => user_id2, :quest_id => quest_id}, :pic => nil, :string => str}, :del}}}
            # TODO: detta:
            # Hur vet användaren att den klarat questen. Förslag på datastruktur: {:notifs, %{:accepted => {:quest_id, quest_id}}, behövs inget annat.
            # Skickas endast internt/tas emot, skickas inte i av klient
            # send :memo_mux, {:user, user_id, {:set, self(), {:notifs, %{:accepted => {:quest_id, quest_id}}, :del}}}
        end
    end
  end

  # :friends => [{:friend, %{:user_id => user_id, :friends => [{:user_id, amanda}, {:user_id, marcus}]}}, etc...]
  defp parse_friends([], friends), do: friends
  defp parse_friends([{:friend, map} | friends], sofar) do
    parse_friends(friends, [{:user_id, map.user_id} | sofar])
  end

  # Get update
  defp get_upd(str) do
    [_, user_id] = str |> String.split(":")
    send :memo_mux, {:user, user_id, {:get, self(), {:user}}}
    receive do
      {:error, error} -> Logger.info(error)
      user_data ->
        {rooms, pics} = user_data.rooms |> get_all_rooms([], [])
        user_data_rooms = user_data |> Map.replace!(:rooms, rooms)
        user_data_rooms_json = Jason.encode!(user_data_rooms)
        {user_data_rooms_json, pics}
    end
  end

  def get_all_rooms([], rooms, pics), do: {rooms, pics}
  def get_all_rooms([map | rest], rooms, pics) do
    send :memo_mux, {:room, map.room_id, {:get, self(), {:room}}}
    receive do
      {:error, error} -> Logger.info(error)
      room_data ->
        pics = [%{:room_id => map.room_id, :pic => room_data.icon} | pics]
        pics = room_data.quest_pics ++ pics
        room_data = room_data |> Map.delete(:icon) |> Map.delete(:quest_pics)
        get_all_rooms(rest, [%{:room_id => map.room_id, :room => room_data} | rooms], pics)
    end
  end

  defp send_update({json, pics}, socket) do
    write_line("200 ", socket)
    write_line(json, socket)
    write_line("\r\n", socket)
    send_all_pics(pics, socket)
  end

  # PICS struktur: %{:room_id => map.room_id, :pic => room_data.icon}, %{:quest_pic_id => quest_pic_id, :pic => <<ByteArray>>}
  defp send_all_pics([], socket), do: write_line("END\r\n", socket)
  defp send_all_pics([picmap | pics], socket) do
    picmap |> Map.fetch(:room_id)
    |> case do
      :error ->
        write_line("pic len=" + length(picmap.pic) + " pic_id:" + picmap.quest_pic_id + "\r\n", socket)
        send_mess(picmap.pic, socket)
      {:ok, :room_id} ->
        write_line("pic len=" + length(picmap.pic) + " pic_id:" + picmap.room_id + "\r\n", socket)
        send_mess(picmap.pic, socket)
    end
    case read_line(socket) do
      "ok" ->
        send_all_pics(pics, socket)
    end
  end

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

  # Skickar data från lista till socket, exempelvis en bild?
  defp send_mess([], socket), do: write_line("\r\n", socket)
  defp send_mess([h|t], socket) do
    case write_line(h, socket) do
      :ok ->  send_mess(t, socket)
      {:error, error} -> Logger.info("send_mess: #{error}")
    end
  end
end
