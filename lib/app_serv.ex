defmodule Serv do
  require Logger

  @doc """
  Starts accepting connections on the given 'port'.
  """
  def accept(port) do
    # http://erlang.org/doc/man/gen_tcp.html
    {:ok, socket} = :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true])

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
      {:error, error} ->
        Logger.info("serve: #{error}")

      mess ->
        parse(mess, socket)
        serve(socket)
    end
  end

  @doc """
  Tar in förfrågan och skickar vidare info baserad på denna
  """
  def parse(mess, socket) do
    # Gör lista av sträng
    {h, tail} = String.split_at(mess, 4)
    # Logger.info("tail: #{tail}")
    case h do
      # Skickar vidare info och startar process om POS request
      "POS " ->
        Logger.info("POS")
        spawn(fn -> pos_req(tail, socket) end)

      # Skickar vidare info och startar process om PUT request
      "PUT " ->
        # Logger.info("PUT?")
        # PUT requests kan vara av olika typ vanlig och PIC
        tail
        |> String.split_at(4)
        |> case do
          {"PIC ", nil} ->
            Logger.info("VARNING: PUT PIC nil")

          {"PIC ", things} ->
            Logger.info("PUT PIC")
            # thing = "id len"
            # spawn fn -> put_pic_req(things, socket) end
            put_pic_req(things, socket)

          _ ->
            Logger.info("PUT!")
            IO.inspect(tail, limit: :infinity)
            spawn(fn -> put_req(tail, socket) end)
        end

      # Skickar vidare info och startar process om DEL request
      "DEL " ->
        Logger.info("DEL")
        spawn(fn -> del_req(tail, socket) end)

      # Skickar vidare info och startar process om PUT request
      "GET " ->
        # Logger.info "GET"
        spawn(fn -> get_req(tail, socket) end)

      _ ->
        IO.inspect(mess, label: "SYNTAX ERROR (╯ರ ~ ರ）╯︵ ┻━┻")
    end
  end

  # Ta hand om POS requests:
  # ID:userID RID:
  # FROM:userID TO:userID +- ROOM:roomID +- QUEST:questID <string> eller en bild som skickas senare
  defp pos_req(str, socket) do
    Logger.info("POS REQ: #{str}")
    [h | _] = String.split(str, " ")

    String.split(h, ":")
    |> case do
      ["ID", user_id] ->
        pos_create_user(user_id)

      ["FROM", user_id] ->
        str
        |> String.split(" ")
        |> case do
          [_, to] ->
            pos_friend_req(to, user_id)
            write_line("201\r\n", socket)

          [_, to, third | string] ->
            [_, user_id2] = to |> String.split(":")

            third
            |> String.split(":")
            |> case do
              ["ROOM", room_id] ->
                pos_req_room(user_id, user_id2, room_id)

              ["QUEST", quest_id] ->
                pos_req_quest(user_id, user_id2, quest_id, string)
            end
        end
    end

    write_line("201\r\n", socket)
  end

  def pos_create_user(user_id) do
    user = %{
      :user_id => user_id,
      :notifs => [],
      :friends => [],
      :rooms => [],
      :has_new => false
    }

    send(:memo_mux, {:user, user_id, {:create_user, user}})
  end

  def pos_friend_req(string, user_id) do
    [_, user_id2] = string |> String.split(":")
    friend_request = %{:friend_request => %{:from => user_id, :to => user_id2}}
    send(:memo_mux, {:user, user_id, {:set, self(), {:notifs, friend_request, :add}}})
    send(:memo_mux, {:user, user_id2, {:set, self(), {:notifs, friend_request, :add}}})
  end

  defp pos_req_room(user_id, user_id2, room_id) do
    room_invite = %{:group_request => %{:from => user_id, :to => user_id2, :group => room_id}}
    send(:memo_mux, {:user, user_id, {:set, self(), {:notifs, room_invite, :add}}})
    send(:memo_mux, {:user, user_id2, {:set, self(), {:notifs, room_invite, :add}}})
  end

  defp pos_req_quest(user_id, user_id2, quest_id, string) do
    quest_sub = %{
      :submitted => %{:from => user_id, :to => user_id2, :quest_id => quest_id},
      :pic => nil,
      :string => string
    }

    send(:memo_mux, {:user, user_id, {:set, self(), {:notifs, quest_sub, :add}}})
    send(:memo_mux, {:user, user_id2, {:set, self(), {:notifs, quest_sub, :add}}})
  end

  # <picID> len:<byte_len> (sendok) <byte[]>
  defp put_pic_req(str, socket) do
    [pic_id, len | _] = str |> String.split(" len:")
    IO.inspect(pic_id, label: "pic_id")
    IO.inspect(len, label: "pic_len")

    # send ok
    write_line("ok\r\n", socket)
    Logger.info("ok sent")

    # Get pic
    pic_mess = read_image([], String.to_integer(len), socket)
    Logger.info("GOT PIC pic_mess lenght: #{Enum.count(pic_mess)}")

    # send ok
    # write_line("201\r\n", socket)
    # Logger.info("ok2 sent")

    # save
    pic_mess
    |> Enum.reverse()
    |> save_pic(pic_id)
  end

  # picID = IMAG@userName@roomName | @missionOwner@missionName@misisonPart@thingName
  # picID = SUBM@userName@roomName@missionOwner@missionName
  defp save_pic(pic, pic_id) do
    pic_id
    |> String.split("@")
    |> case do
      ["IMAG", owner_id, room_id] ->
        # Spara rumbild
        room_id = "#{owner_id}@#{room_id}"
        send(:memo_mux, {:room, room_id, {:set, self(), {:room, :icon, pic, :add}}})

      ["IMAG", owner_id, room_id, quest_owner, quest_id, quest_part_id] ->
        # Spara questbilder
        room_id = "#{owner_id}@#{room_id}"
        send(:memo_mux, {:room, room_id, {:set, self(), {:quest_pic, pic_id, pic, :add}}})

      ["SUBM", owner_id, room_id, quest_owner, quest_id] ->
        # Submitted quest-pictures
        # TODO:
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
        IO.inspect(len, label: "read_image rest len")

        [read_bytes(socket, len) | mem]
        |> read_image(0, socket)
    end
  end

  # Tar hand om put requests som ser ut som följande:
  # ID:user_id RID:thing@userName@roomName | @missionName <JSON>
  # Se lib/doc.ex eller den formaterade versionen docs/Docs.html om hur memo_mux funkar
  # thing@userName@roomName@ | missionOwner@missionName | @misisonPart | @thingName
  defp put_req(str, socket) do
    # Logger.info("PUT REQ")
    [id, rid | _] = str |> String.split(" ")
    {_, json} = str |> String.split_at(String.length(id) + String.length(rid) + 2)
    decoded = Jason.decode!(json)
    IO.inspect(decoded, label: "decoded json")

    [_, res_id] = rid |> String.split(":")

    String.split(res_id, "@")
    |> case do
      # Room
      [_, owner_id, room_id] ->
        Logger.info("put_req Room")
        put_room(decoded, owner_id, room_id, socket)

      # Quest
      [_, owner_id, room_name, mission_owner, mission_id] ->
        room_id = "#{owner_id}@#{room_name}"
        quest_id = "#{owner_id}@#{room_name}@#{mission_owner}@#{mission_id}"
        IO.inspect(room_id, label: "QUEST room_id")
        IO.inspect(quest_id, label: "QUEST quest_id")
        IO.inspect(json, label: "QUEST json")
        send(:memo_mux, {:room, room_id, {:set, self(), {:quest, quest_id, json, :add}}})
    end

    write_line("201\r\n", socket)
  end

  defp put_room(decoded, owner_id, room_name, socket) do
    room_id = "#{owner_id}@#{room_name}"

    {:ok, owner} = decoded |> Map.fetch("owner")
    send(:memo_mux, {:room, room_id, {:set, self(), {:room, :owner, owner, :add}}})

    {:ok, room_alias} = decoded |> Map.fetch("roomName")
    send(:memo_mux, {:room, room_id, {:set, self(), {:room, :name, room_alias, :add}}})

    {:ok, desc} = decoded |> Map.fetch("description")
    send(:memo_mux, {:room, room_id, {:set, self(), {:room, :topic, desc, :add}}})
  end

  # "ID:userID RID:resourceID"
  # "FROM:userID TO:userID +- GROUP:groupID +- QUEST:questID"
  defp del_req(str, socket) do
    str
    |> String.split(":")
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
    str
    |> String.split(" ")
    |> case do
      [userID, userID2] ->
        del_friend_req(userID, userID2, socket)

      [userID, userID2, third] ->
        [_, user_id] = userID |> String.split(":")
        [_, user_id2] = userID2 |> String.split(":")

        third
        |> String.split(":")
        |> case do
          ["GROUP", room_id] ->
            del_room_req(room_id, user_id, user_id2, socket)

          ["QUEST", quest_id | string] ->
            del_quest_subm(user_id, user_id2, quest_id, string, socket)
        end
    end

    write_line("201\r\n", socket)
  end

  defp del_friend_req(userID, userID2, socket) do
    [_, user_id] = userID |> String.split(":")
    [_, user_id2] = userID2 |> String.split(":")
    friend_request = %{:friend_request => %{:from => user_id, :to => user_id2}}
    send(:memo_mux, {:user, user_id, {:set, self(), {:notifs, friend_request, :del}}})
    send(:memo_mux, {:user, user_id2, {:set, self(), {:notifs, friend_request, :del}}})
  end

  defp del_room_req(room_id, user_id, user_id2, socket) do
    room_invite = %{:room_invite => %{:from => user_id, :to => user_id2, :group => room_id}}
    send(:memo_mux, {:user, user_id, {:set, self(), {:notifs, room_invite, :del}}})
    send(:memo_mux, {:user, user_id2, {:set, self(), {:notifs, room_invite, :del}}})
  end

  defp del_quest_subm(user_id, user_id2, quest_id, string, socket) do
    quest_sub = %{
      :submitted => %{:from => user_id, :to => user_id2, :quest_id => quest_id},
      :pic => nil,
      :string => string
    }

    send(:memo_mux, {:user, user_id, {:set, self(), {:notifs, quest_sub, :del}}})
    send(:memo_mux, {:user, user_id2, {:set, self(), {:notifs, quest_sub, :del}}})
  end

  # Tar emot:
  # "ID:userID RID:resourceID"
  # Om du tar bort ett room skickas detta vidare till roomhandler
  # Om du tar bort en mission skickas detta vidare till roomhandler
  # TODO: bryt ut längre strukturer ur send för att göra lättare att läsa.
  defp del_room_quest(str, socket) do
    [_, resource_id] = str |> String.split(" ")
    [_, resource_id] = resource_id |> String.split("RID:")

    resource_id
    |> String.split("@")
    |> case do
      [_, owner_id, room_id] ->
        send(
          :memo_mux,
          {:room, "#{owner_id}@#{room_id}", {:set, self(), {:room, "#{}@#{room_id}", :del}}}
        )

        receive do
          :ok ->
            write_line("201\r\n", socket)

          error ->
            Logger.info(error)
        end

      [_, owner_id, room_id, mission_owner, mission_id] ->
        send(
          :memo_mux,
          {:room, "#{owner_id}@#{room_id}",
           {:set, self(),
            {:quest, "#{owner_id}@#{room_id}@#{mission_owner}@#{mission_id}", nil, :del}}}
        )

        #Tror inte du får något svar här?
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
  defp get_req(str, socket) do
    # Logger.info("GET REQ: #{str}")
    str
    |> String.split(" ")
    |> case do
      [user] ->
        get_upd(user) |> send_update(socket)

      [from, to] ->
        get_friend_req(from, to, socket)
        write_line("201\r\n", socket)

      [from, to, third] ->
        [_, user_id] = from |> String.split(":")
        [_, user_id2] = to |> String.split(":")

        third
        |> String.split(":")
        |> case do
          ["GROUP", room_id] ->
            get_room_req(user_id, user_id2, room_id, socket)
            write_line("201\r\n", socket)

          ["QUEST", quest_id | str] ->
            get_quest_subm(user_id, user_id2, quest_id, str, socket)
            write_line("201\r\n", socket)
        end

      _ ->
        Logger.info("wtf")
    end
  end

  defp get_friend_req(from, to, socket) do
    [_, user_id] = from |> String.split(":")
    [_, user_id2] = to |> String.split(":")

    # lägg till en ny friend på user_id och user_id2
    # plocka ut alla vänner från user_id, bygg denna person som "vän"
    send(:memo_mux, {:user, user_id, {:get, self(), {:friends}}})

    list1 =
      receive do
        friends ->
          parse_friends(friends, [])
      end

    send(:memo_mux, {:user, user_id2, {:get, self(), {:friends}}})

    list2 =
      receive do
        friends ->
          parse_friends(friends, [])
      end

    # add new friends:
    friend_req1 = %{:friend => %{:user_id => user_id2, :friends => list1}}
    friend_req2 = %{:friend => %{:user_id => user_id, :friends => list2}}
    send(:memo_mux, {:user, user_id, {:set, self(), {:friend, user_id2, friend_req1, :add}}})
    send(:memo_mux, {:user, user_id2, {:set, self(), {:friends, user_id2, friend_req2, :add}}})
    # Delete req
    friend_req = %{:friend_request => %{:from => user_id, :to => user_id2}}
    send(:memo_mux, {:user, user_id, {:set, self(), {:notifs, friend_req, :del}}})
    send(:memo_mux, {:user, user_id2, {:set, self(), {:notifs, friend_req, :del}}})
  end

  defp get_room_req(user_id, user_id2, room_id, socket) do
    # ta bort grupp/rum förfrågan
    room_invite = %{:room_invite => %{:from => user_id, :to => user_id2, :group => room_id}}
    send(:memo_mux, {:user, user_id, {:set, self(), {:notifs, room_invite, :del}}})
    send(:memo_mux, {:user, user_id2, {:set, self(), {:notifs, room_invite, :del}}})
    # Lägg till rummet i user-data:
    send(:memo_mux, {:user, user_id2, {:set, self(), {:room, room_id, :add}}})
    # lägg till som member i rummet (room_data):
    send(:memo_mux, {:room, room_id, {:set, self(), {:room, :users, %{:user => user_id2}, :add}}})
  end

  defp get_quest_subm(user_id, user_id2, quest_id, str, socket) do
    quest_sub = %{
      :submitted => %{:from => user_id, :to => user_id2, :quest_id => quest_id},
      :pic => nil,
      :string => nil
    }

    send(:memo_mux, {:user, user_id, {:set, self(), {:notifs, quest_sub, :del}}})
    send(:memo_mux, {:user, user_id2, {:set, self(), {:notifs, quest_sub, :del}}})
    quest_accept = %{:accepted => %{:quest_id => quest_id}}
    send(:memo_mux, {:user, user_id, {:set, self(), {:notifs, quest_accept, :del}}})
  end

  defp parse_friends([], friends), do: friends

  defp parse_friends([{:friend, map} | friends], sofar) do
    parse_friends(friends, [{:user_id, map.user_id} | sofar])
  end

  # Get update
  defp get_upd(str) do
    [_, user_id] = str |> String.split(":")
    # IO.inspect(user_id)
    # IO.inspect(str)
    send(:memo_mux, {:user, user_id, {:get, self(), {:user}}})

    receive do
      {:error, error} ->
        Logger.info("ERROR IS HERE #{error}")

      user_data ->
        # Logger.info("get_upd user_data")
        {rooms, pics} = user_data.rooms |> get_all_rooms([], [])
        IO.inspect(rooms, label: "get_upd rooms:")
        user_data_rooms = user_data |> Map.replace!(:rooms, rooms)
        user_data_rooms_json = Jason.encode!(user_data_rooms)
        {user_data_rooms_json, pics}
    end
  end

  def get_all_rooms([], rooms, pics), do: {rooms, pics}

  def get_all_rooms([map | rest], rooms, pics) do
    Logger.info("############## get_all_rooms: #{map.room_id}")
    send(:memo_mux, {:room, map.room_id, {:get, self(), {:room}}})

    receive do
      {:error, error} ->
        Logger.info(error)

      room_data ->
        IO.inspect(room_data)
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
    IO.inspect(json, label: "sent JSON")
    send_all_pics(pics, socket)
  end

  # PICS struktur: %{:room_id => map.room_id, :pic => room_data.icon}, %{:quest_pic_id => quest_pic_id, :pic => <<ByteArray>>}
  defp send_all_pics([], socket), do: write_line("END\r\n", socket)

  defp send_all_pics([picmap | pics], socket) do
    length = (length(picmap.pic) - 1) * 1024 + byte_size(List.last(picmap.pic))

    picmap
    |> Map.fetch(:room_id)
    |> case do
      :error ->
        write_line("pic_len=#{length} pic_id=#{picmap.quest_pic_id} \r\n", socket)
        send_mess(picmap.pic, socket)

      {:ok, _} ->
        write_line("pic_len=#{length} pic_id=#{picmap.room_id} \r\n", socket)
        # TODO: READLINE - OK MELLAN SKICKNINGAR
        send_mess(picmap.pic, socket)
    end

    send_all_pics(pics, socket)
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
    # How this know where to stop is magic.
    case :gen_tcp.recv(socket, 0) do
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

  defp send_mess([h | t], socket) do
    case write_line(h, socket) do
      :ok -> send_mess(t, socket)
      {:error, error} -> Logger.info("send_mess: #{error}")
    end
  end

  defp all_oks(0), do: :ok

  defp all_oks(int) do
    receive do
      {:error, error} -> error
      {:memo, :ok} -> all_oks(int - 1)
    end
  end
end
