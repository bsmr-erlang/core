Code.require_file "../test_helper.exs", __DIR__

defmodule Base.SysTest do
  use ExUnit.Case

  use Base.Behaviour
  use Base.Sys.Behaviour

  def init(parent, debug, fun) do
    Base.init_ack()
    loop(fun, parent, debug)
  end

  def loop(fun, parent, debug) do
    Base.Sys.receive(__MODULE__, fun, parent, debug) do
      { __MODULE__, from, { :event, event } } ->
        debug = Base.Debug.event(debug, event)
        Base.reply(from, :ok)
        loop(fun, parent, debug)
      { __MODULE__, from, :eval } ->
        Base.reply(from, fun.())
        loop(fun, parent, debug)
    end
  end

  def system_get_state(fun), do: fun.()

  def system_update_state(fun, update) do
    fun = update.(fun)
    { fun, fun }
  end

  def system_get_data(fun), do: fun.()

  def system_change_data(_oldfun, _mod, _oldvsn, newfun), do: newfun.()

  def system_continue(fun, parent, debug), do: loop(fun, parent, debug)

  def system_terminate(fun, _parent, _debug, _reason) do
    fun.()
  end

  setup_all do
    File.touch(Path.join(__DIR__, "logfile"))
    TestIO.setup_all()
  end

  setup do
    TestIO.setup()
  end

  teardown context do
    TestIO.teardown(context)
  end

  teardown_all do
    File.rm(Path.join(__DIR__, "logfile"))
    TestIO.teardown_all()
  end

  test "ping" do
    pid = Base.spawn_link(__MODULE__, fn() -> nil end)
    assert Base.Sys.ping(pid) === :pong
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "ping :gen_server" do
    { :ok, pid } = GS.start_link(fn() -> { :ok, nil } end)
  assert Base.Sys.ping(pid) === :pong
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "ping :gen_event" do
    { :ok, pid } = GE.start_link(fn() -> { :ok, nil } end)
    assert Base.Sys.ping(pid) === :pong
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "ping :gen_fsm" do
    { :ok, pid} = GFSM.start_link(fn() -> {:ok, :state, nil} end)
    assert Base.Sys.ping(pid) === :pong
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_state" do
    ref = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref end)
    assert Base.Sys.get_state(pid) === ref
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_state that raises exception" do
    exception = ArgumentError[message: "hello"]
    pid = Base.spawn_link(__MODULE__, fn() -> raise(exception, []) end)
    assert_raise Base.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_get_state/1)} raised an exception\n" <>
      "   (ArgumentError) hello",
      fn() -> Base.Sys.get_state(pid) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_state that throws" do
    pid = Base.spawn_link(__MODULE__, fn() -> throw(:hello) end)
    assert_raise Base.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_get_state/1)} raised an exception\n" <>
      "   (Base.UncaughtThrowError) uncaught throw: :hello",
      fn() -> Base.Sys.get_state(pid) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_state that exits" do
    pid = Base.spawn_link(__MODULE__, fn() -> exit(:hello) end)
    assert_raise Base.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_get_state/1)} exited with reason: :hello",
      fn() -> Base.Sys.get_state(pid) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_state :gen_server" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    assert Base.Sys.get_state(pid) === ref
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_state :gen_event" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    assert Base.Sys.get_state(pid) === [{GE, false, ref}]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_state :gen_fsm" do
    ref = make_ref()
    { :ok, pid} = GFSM.start_link(fn() -> {:ok, :state, ref} end)
    assert Base.Sys.get_state(pid) === { :state, ref }
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_state" do
    ref1 = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref1 end)
    ref2 = make_ref()
    fun = fn() -> ref2 end
    assert Base.Sys.set_state(pid, fun) === :ok
    assert Base.call(pid, __MODULE__, :eval, 500) === ref2, "state not set"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "update_state" do
    ref1 = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref1 end)
    ref2 = make_ref()
    update = fn(fun) -> ( fn() -> { fun.(), ref2 } end ) end
    Base.Sys.update_state(pid, update)
    assert Base.call(pid, __MODULE__, :eval, 500) === { ref1, ref2 },
      "state not updated"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "update_state that raises exception" do
    ref = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref end)
    exception = ArgumentError[message: "hello"]
    update = fn(_fun) -> raise(exception, []) end
    assert_raise Base.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_update_state/2)} raised an exception\n" <>
      "   (ArgumentError) hello",
      fn() -> Base.Sys.update_state(pid, update) end
    assert Base.call(pid, __MODULE__, :eval, 500) === ref, "state changed"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "update_state that throws" do
    ref = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref end)
    update = fn(_fun) -> throw(:hello) end
    assert_raise Base.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_update_state/2)} raised an exception\n" <>
      "   (Base.UncaughtThrowError) uncaught throw: :hello",
      fn() -> Base.Sys.update_state(pid, update) end
    assert Base.call(pid, __MODULE__, :eval, 500) === ref, "state changed"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "update_state that exits" do
    ref = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref end)
    update = fn(_fun) -> exit(:hello) end
    assert_raise Base.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_update_state/2)} exited with reason: :hello",
      fn() -> Base.Sys.update_state(pid, update) end
    assert Base.call(pid, __MODULE__, :eval, 500) === ref, "state changed"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "update_state :gen_server" do
    ref1 = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref1 } end)
    ref2 = make_ref()
    update = fn(state) -> { state, ref2 } end
    assert Base.Sys.update_state(pid, update) === { ref1, ref2 }
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "update_state :gen_event" do
    ref1 = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref1 } end)
    ref2 = make_ref()
    update = fn({mod, id, state}) -> { mod, id, { state, ref2 } } end
    assert Base.Sys.update_state(pid, update) === [{GE, false, { ref1, ref2 } }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "update_state :gen_fsm" do
    ref1 = make_ref()
    { :ok, pid} = GFSM.start_link(fn() -> {:ok, :state, ref1} end)
    ref2 = make_ref()
    update = fn({ state_name, state_data }) ->
      { state_name, { state_data, ref2 } }
    end
    assert Base.Sys.update_state(pid, update) === { :state, { ref1, ref2 } }
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status" do
    ref = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref end)
    status = Base.Sys.get_status(pid)
    assert status[:module] === __MODULE__
    assert status[:data] === ref
    assert status[:pid] === pid
    assert status[:name] === pid
    assert status[:log] === []
    assert status[:stats] === nil
    assert status[:sys_status] === :running
    assert status[:parent] === self()
    assert Map.has_key?(status, :dictionary)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status with log and 2 events" do
    ref = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref end,
      [{ :debug, [{ :log, 10 }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    status = Base.Sys.get_status(pid)
    assert status[:log] === [ { :event, 1}, { :event, 2} ]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status with stats and 1 cast message" do
    ref = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref end,
      [{ :debug, [{ :stats, true }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :in, :hello } }, 500)
    status = Base.Sys.get_status(pid)
    stats = status[:stats]
    assert is_map(stats), "stats not returned"
    assert stats[:in] === 1
    assert stats[:out] === 0
    assert is_integer(stats[:reductions])
    assert stats[:start_time] <= stats[:current_time]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status that raises exception" do
    exception = ArgumentError[message: "hello"]
    pid = Base.spawn_link(__MODULE__, fn() -> raise(exception, []) end)
    assert_raise Base.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_get_data/1)} raised an exception\n" <>
      "   (ArgumentError) hello",
      fn() -> Base.Sys.get_status(pid) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status that throws" do
    pid = Base.spawn_link(__MODULE__, fn() -> throw(:hello) end)
    assert_raise Base.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_get_data/1)} raised an exception\n" <>
      "   (Base.UncaughtThrowError) uncaught throw: :hello",
      fn() -> Base.Sys.get_status(pid) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status that exits" do
    pid = Base.spawn_link(__MODULE__, fn() -> exit(:hello) end)
    assert_raise Base.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_get_data/1)} exited with reason: :hello",
      fn() -> Base.Sys.get_status(pid) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test ":sys get_status" do
    ref = make_ref()
    { :ok, pid } = Base.start_link(__MODULE__, fn() -> ref end)
    parent = self()
    { :dictionary, pdict } = Process.info(pid, :dictionary)
    assert { :status, ^pid, { :module, Base.Sys },
      [^pdict, :running, ^parent, [], status] } = :sys.get_status(pid)
    # copy the format of gen_* :sys.status's. Length-3 list, first term is
    # header tuple, second is general information in :data tuple supplied by all
    # callbacks, and third is specific to the callback.
    assert [{ :header, header }, { :data, data1 }, { :data, data2 }] = status
    assert header === String.to_char_list!("Status for " <>
      "#{inspect(__MODULE__)} #{inspect(pid)}")
    assert List.keyfind(data1, 'Status', 0) === { 'Status', :running }
    assert List.keyfind(data1, 'Parent', 0) === { 'Parent', self() }
    assert List.keyfind(data1, 'Logged events', 0) === { 'Logged events', [] }
    assert List.keyfind(data1, 'Statistics', 0) === { 'Statistics',
      :no_statistics }
    assert List.keyfind(data1, 'Name', 0) === { 'Name', pid }
    assert List.keyfind(data1, 'Module', 0) === { 'Module', __MODULE__ }
    assert List.keyfind(data2, 'Module data', 0) === { 'Module data', ref }
    assert List.keyfind(data2, 'Module error', 0) === nil
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test ":sys.get_status with exception" do
    exception = ArgumentError[message: "hello"]
    pid = Base.spawn_link(__MODULE__, fn() -> raise(exception, []) end)
    assert { :status, ^pid, { :module, Base.Sys },
      [_, _, _, _, status] } = :sys.get_status(pid)
    assert [{ :header, _header }, { :data, _data1 }, { :data, data2 }] = status
    # error like 17.0 format for :sys.get_state/replace_stats
    exception2 = Base.Sys.CallbackError[action: &__MODULE__.system_get_data/1,
      reason: exception]
    assert List.keyfind(data2, 'Module error', 0) === { 'Module error',
      { :callback_failed, { Base.Sys, :format_status },
        { :error, exception2 } } }
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test ":sys.get_status with log" do
    ref = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref end,
      [{ :debug, [{ :log, 10 }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 2 } }, 500) 
    assert { :status, ^pid, { :module, Base.Sys },
      [_, _, _, debug, status] } = :sys.get_status(pid)
    assert [{ :header, _header }, { :data, data1 }, { :data, _data2 }] = status
    # This is how gen_* displays the log
    sys_log = :sys.get_debug(:log, debug, [])
    assert List.keyfind(data1, 'Logged events', 0) === { 'Logged events',
      sys_log }
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status :gen_server" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    status = Base.Sys.get_status(pid)
    assert status[:module] === :gen_server
    assert status[:data] === ref
    assert status[:pid] === pid
    assert status[:name] === pid
    assert status[:log] === []
    assert status[:stats] === nil
    assert status[:sys_status] === :running
    assert status[:parent] === self()
    assert Map.has_key?(status, :dictionary)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status :gen_event" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    status = Base.Sys.get_status(pid)
    assert status[:module] === :gen_event
    assert status[:data] === [{ GE, false, ref}]
    assert status[:pid] === pid
    assert status[:name] === pid
    assert status[:log] === []
    assert status[:stats] === nil
    assert status[:sys_status] === :running
    assert status[:parent] === self()
    assert Map.has_key?(status, :dictionary)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status :gen_fsm" do
    ref = make_ref()
    { :ok, pid} = GFSM.start_link(fn() -> {:ok, :state, ref} end)
    status = Base.Sys.get_status(pid)
    assert status[:module] === :gen_fsm
    assert status[:data] === { :state, ref }
    assert status[:pid] === pid
    assert status[:name] === pid
    assert status[:log] === []
    assert status[:stats] === nil
    assert status[:sys_status] === :running
    assert status[:parent] === self()
    assert Map.has_key?(status, :dictionary)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status :gen_server with log" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end, [{ :log, 10 }])
    Process.send(pid, { :msg, 1 })
    Process.send(pid, { :msg, 2 })
    status = Base.Sys.get_status(pid)
    assert status[:log] === [{ :in, { :msg, 1 } }, { :noreply, ref },
      { :in, { :msg, 2 } }, { :noreply, ref }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status :gen_fsm with log" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end,
      [{ :log, 10 }])
    Process.send(pid, { :msg, 1 })
    Process.send(pid, { :msg, 2 })
    status = Base.Sys.get_status(pid)
    assert status[:log] === [{ :in, { :msg, 1 } }, :return,
      { :in, { :msg, 2 } }, :return]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_data" do
    ref = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref end)
    assert Base.Sys.get_data(pid) === ref
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data" do
    ref1 = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref1 end)
    ref2 = make_ref()
    fun = fn() -> fn() -> ref2 end end
    assert Base.Sys.suspend(pid) === :ok
    assert Base.Sys.change_data(pid, __MODULE__, nil, fun) === :ok
    assert Base.Sys.resume(pid) === :ok
    assert Base.call(pid, __MODULE__, :eval, 500) === ref2, "data not changed"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data that raises exception" do
    ref = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref end)
    Base.Sys.suspend(pid)
    exception = ArgumentError[message: "hello"]
    extra = fn() -> raise(exception, []) end
    assert_raise Base.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_change_data/4)} raised an exception\n" <>
      "   (ArgumentError) hello",
      fn() -> Base.Sys.change_data(pid, __MODULE__, nil, extra) end
    Base.Sys.resume(pid)
    assert Base.call(pid, __MODULE__, :eval, 500) === ref, "data changed"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data that throws" do
    ref = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref end)
    Base.Sys.suspend(pid)
    extra = fn() -> throw(:hello) end
    assert_raise Base.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_change_data/4)} raised an exception\n" <>
      "   (Base.UncaughtThrowError) uncaught throw: :hello",
      fn() -> Base.Sys.change_data(pid, __MODULE__, nil, extra) end
    Base.Sys.resume(pid)
    assert Base.call(pid, __MODULE__, :eval, 500) === ref, "data changed"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data that exits" do
    ref = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref end)
    Base.Sys.suspend(pid)
    extra = fn() -> exit(:hello) end
    assert_raise Base.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_change_data/4)} exited with reason: :hello",
      fn() -> Base.Sys.change_data(pid, __MODULE__, nil, extra) end
    Base.Sys.resume(pid)
    assert Base.call(pid, __MODULE__, :eval, 500) === ref, "data changed"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data while running" do
    ref1 = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref1 end)
    ref2 = make_ref()
    extra = fn() -> fn() -> ref2 end end
    assert_raise ArgumentError, "#{inspect(pid)} is running",
      fn() -> Base.Sys.change_data(pid, __MODULE__, nil, extra) end
    assert Base.call(pid, __MODULE__, :eval, 500) === ref1, "data changed"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_server" do
    ref1 = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref1 } end)
    Base.Sys.suspend(pid)
    ref2 = make_ref()
    extra = fn() -> { :ok, ref2 } end
    assert Base.Sys.change_data(pid, GS, nil, extra) === :ok
    Base.Sys.resume(pid)
    assert :sys.get_state(pid) === ref2
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_server with raise" do
    ref1 = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref1 } end)
    Base.Sys.suspend(pid)
    exception = ArgumentError[message: "hello"]
    extra = fn() -> raise(exception, []) end
    assert_raise Base.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ArgumentError) hello",
      fn() -> Base.Sys.change_data(pid, GS, nil, extra) end
    Base.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_server with erlang badarg" do
    ref1 = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref1 } end)
    Base.Sys.suspend(pid)
    extra = fn() -> :erlang.error(:badarg, []) end
    assert_raise Base.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ArgumentError) argument error",
      fn() -> Base.Sys.change_data(pid, GS, nil, extra) end
    Base.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_server with erlang error" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    Base.Sys.suspend(pid)
    extra = fn() -> :erlang.error(:custom_erlang, []) end
    assert_raise Base.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ErlangError) erlang error: :custom_erlang",
      fn() -> Base.Sys.change_data(pid, GS, nil, extra) end
    Base.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_server with exit" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    Base.Sys.suspend(pid)
    extra = fn() -> exit(:exit_reason) end
    assert_raise Base.Sys.CallbackError,
      "unknown function exited with reason: :exit_reason",
      fn() -> Base.Sys.change_data(pid, GS, nil, extra) end
    Base.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_server with bad return" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    Base.Sys.suspend(pid)
    extra = fn() -> :badreturn end
    assert_raise Base.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (MatchError) no match of right hand side value: :badreturn",
      fn() -> Base.Sys.change_data(pid, GS, nil, extra) end
    Base.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_event" do
    ref1 = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref1 } end)
    :ok = Base.Sys.suspend(pid)
    ref2 = make_ref()
    extra = fn() -> { :ok, ref2 } end
    assert Base.Sys.change_data(pid, GE, nil, extra) === :ok
    Base.Sys.resume(pid)
    assert :sys.get_state(pid) === [{GE, false, ref2 }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_event with raise" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    Base.Sys.suspend(pid)
    exception = ArgumentError[message: "hello"]
    extra = fn() -> raise(exception, []) end
    assert_raise Base.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ArgumentError) hello",
      fn() -> Base.Sys.change_data(pid, GE, nil, extra) end
    Base.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_event with erlang badarg" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    Base.Sys.suspend(pid)
    extra = fn() -> :erlang.error(:badarg, []) end
    assert_raise Base.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ArgumentError) argument error",
      fn() -> Base.Sys.change_data(pid, GE, nil, extra) end
    Base.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_event with erlang error" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    Base.Sys.suspend(pid)
    extra = fn() -> :erlang.error(:custom_erlang, []) end
    assert_raise Base.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ErlangError) erlang error: :custom_erlang",
      fn() -> Base.Sys.change_data(pid, GE, nil, extra) end
    Base.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_event with exit" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    Base.Sys.suspend(pid)
    extra = fn() -> exit(:exit_reason) end
    assert_raise Base.Sys.CallbackError,
      "unknown function exited with reason: :exit_reason",
      fn() -> Base.Sys.change_data(pid, GE, nil, extra) end
    Base.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_event with bad return" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    Base.Sys.suspend(pid)
    extra = fn() -> :badreturn end
    assert_raise Base.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (MatchError) no match of right hand side value: :badreturn",
      fn() -> Base.Sys.change_data(pid, GE, nil, extra) end
    Base.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_fsm" do
    ref1 = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref1 } end)
    Base.Sys.suspend(pid)
    ref2 = make_ref()
    extra = fn() -> { :ok, :state, ref2 } end
    assert Base.Sys.change_data(pid, GFSM, nil, extra) === :ok
    Base.Sys.resume(pid)
    assert :sys.get_state(pid) === { :state, ref2 }
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_fsm with raise" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    Base.Sys.suspend(pid)
    exception = ArgumentError[message: "hello"]
    extra = fn() -> raise(exception, []) end
    assert_raise Base.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ArgumentError) hello",
      fn() -> Base.Sys.change_data(pid, GFSM, nil, extra) end
    Base.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_fsm with erlang badarg" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    Base.Sys.suspend(pid)
    extra = fn() -> :erlang.error(:badarg, []) end
    assert_raise Base.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ArgumentError) argument error",
      fn() -> Base.Sys.change_data(pid, GFSM, nil, extra) end
    Base.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_fsm with erlang error" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    Base.Sys.suspend(pid)
    extra = fn() -> :erlang.error(:custom_erlang, []) end
    assert_raise Base.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ErlangError) erlang error: :custom_erlang",
      fn() -> Base.Sys.change_data(pid, GFSM, nil, extra) end
    Base.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_fsm with exit" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    Base.Sys.suspend(pid)
    extra = fn() -> exit(:exit_reason) end
    assert_raise Base.Sys.CallbackError,
      "unknown function exited with reason: :exit_reason",
      fn() -> Base.Sys.change_data(pid, GFSM, nil, extra) end
    Base.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_fsm with bad return" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    Base.Sys.suspend(pid)
    extra = fn() -> :badreturn end
    assert_raise Base.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (MatchError) no match of right hand side value: :badreturn",
      fn() -> Base.Sys.change_data(pid, GFSM, nil, extra) end
    Base.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log with 0 events" do
    ref1 = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
    [{ :debug, [{ :log, 10 }] }])
    assert Base.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log with 2 events" do
    ref1 = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :log, 10 }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert Base.Sys.get_log(pid) === [{ :event, 1 }, { :event, 2 }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log with no logging and 2 events" do
    ref1 = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref1 end)
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert Base.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log :gen_server with 0 events" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end, [{ :log, 10 }])
    assert Base.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log :gen_server with 2 events" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end, [{ :log, 10 }])
    Process.send(pid, 1)
    Process.send(pid, 2)
    assert Base.Sys.get_log(pid) === [{ :in, 1 }, { :noreply, ref },
      { :in, 2 }, { :noreply, ref }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log :gen_server with no logging" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    assert Base.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log :gen_event with no logging (can never log)" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    assert Base.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log :gen_fsm with 0 events" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end,
      [{ :log, 10 }])
    assert Base.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log :gen_fsm with 2 events" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end,
      [{ :log, 10 }])
    Process.send(pid, 1)
    Process.send(pid, 2)
    assert Base.Sys.get_log(pid) === [{ :in, 1 }, :return, { :in, 2 }, :return]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log :gen_fsm with no logging" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    assert Base.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "print_log with 2 events" do
    ref1 = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :log, 10 }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert Base.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Base.Debug #{inspect(pid)} event log:\n" <>
    "** Base.Debug #{inspect(pid)} #{inspect({ :event, 1 })}\n" <>
    "** Base.Debug #{inspect(pid)} #{inspect({ :event, 2 })}\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log with 0 events" do
    ref1 = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :log, 10 }] }])
    assert Base.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Base.Debug #{inspect(pid)} event log is empty\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log with no logging and 2 events" do
    ref1 = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref1 end)
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert Base.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Base.Debug #{inspect(pid)} event log is empty\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log with cast message in" do
    ref1 = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :log, 10 }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :in, :hello } }, 500)
    assert Base.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Base.Debug #{inspect(pid)} event log:\n" <>
    "** Base.Debug #{inspect(pid)} message in: :hello\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log with call message in" do
    ref1 = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :log, 10 }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :in, :hello, self() } }, 500)
    assert Base.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Base.Debug #{inspect(pid)} event log:\n" <>
    "** Base.Debug #{inspect(pid)} message in (from #{inspect(self())}): " <>
    ":hello\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log with message out" do
    ref1 = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :log, 10 }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :out, :hello, self() } }, 500)
    assert Base.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Base.Debug #{inspect(pid)} event log:\n" <>
    "** Base.Debug #{inspect(pid)} message out (to #{inspect(self())}): " <>
    ":hello\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log :gen_server with 0 events" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end, [{ :log, 10 }])
    assert Base.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Base.Debug #{inspect(pid)} event log is empty\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log :gen_server with 2 events" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end, [{ :log, 10 }])
    Process.send(pid, 1)
    Process.send(pid, 2)
    assert Base.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    erl_pid = inspect_erl(pid)
    erl_ref = inspect_erl(ref)
    report = "** Base.Debug #{inspect(pid)} event log:\n" <>
    "*DBG* #{erl_pid} got 1\n" <>
    "*DBG* #{erl_pid} new state #{erl_ref}\n" <>
    "*DBG* #{erl_pid} got 2\n" <>
    "*DBG* #{erl_pid} new state #{erl_ref}\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log :gen_server with no logging" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    assert Base.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Base.Debug #{inspect(pid)} event log is empty\n" <>
    "\n"
   assert TestIO.binread() === report
  end

  test "print_log :gen_event with no logging (can never log)" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    assert Base.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Base.Debug #{inspect(pid)} event log is empty\n" <>
    "\n"
   assert TestIO.binread() === report
  end

  test "print_log :gen_fsm with 0 events" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end,
      [{ :log, 10 }])
    assert Base.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Base.Debug #{inspect(pid)} event log is empty\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log :gen_fsm with 2 events" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end,
      [{ :log, 10 }])
    Process.send(pid, 1)
    Process.send(pid, 2)
    assert Base.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    erl_pid = inspect_erl(pid)
    report = "** Base.Debug #{inspect(pid)} event log:\n" <>
    "*DBG* #{erl_pid} got 1 in state state\n" <>
    "*DBG* #{erl_pid} switched to state state\n" <>
    "*DBG* #{erl_pid} got 2 in state state\n" <>
    "*DBG* #{erl_pid} switched to state state\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log :gen_fsm with no logging" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    assert Base.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Base.Debug #{inspect(pid)} event log is empty\n" <>
    "\n"
   assert TestIO.binread() === report
  end

  test "set_log 10 with 2 events" do
    ref1 = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref1 end)
    assert Base.Sys.set_log(pid, 10) === :ok
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert Base.Sys.get_log(pid) === [{ :event, 1 }, { :event, 2 }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_log 1 with 2 events" do
    ref1 = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref1 end)
    assert Base.Sys.set_log(pid, 1) === :ok
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert Base.Sys.get_log(pid) === [{ :event, 2 }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_log 0 with 1 event before and 1 event after" do
    ref1 = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :log, 10 }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    assert Base.Sys.set_log(pid, 0) === :ok
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert Base.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_log 10 :gen_server with 2 events" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    assert Base.Sys.set_log(pid, 10) === :ok
    Process.send(pid, 1)
    Process.send(pid, 2)
    assert Base.Sys.get_log(pid) === [{ :in, 1 }, { :noreply, ref },
      { :in, 2 }, { :noreply, ref }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_log 1 :gen_server with 2 events" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    assert Base.Sys.set_log(pid, 1) === :ok
    Process.send(pid, 1)
    assert Base.Sys.get_log(pid) === [{ :noreply, ref }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_log 0 :gen_server with 2 events before and 2 event after" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end, [{ :log, 10 }])
    Process.send(pid, 1)
    assert Base.Sys.set_log(pid, 0) === :ok
    Process.send(pid, 2)
    assert Base.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_log 10 :gen_fsm with 4 events" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    assert Base.Sys.set_log(pid, 10) === :ok
    Process.send(pid, 1)
    Process.send(pid, 2)
    assert Base.Sys.get_log(pid) === [{ :in, 1 }, :return, { :in, 2 }, :return]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_log 1 :gen_fsm with 2 events" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    assert Base.Sys.set_log(pid, 1) === :ok
    Process.send(pid, 1)
    assert Base.Sys.get_log(pid) === [:return]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_log 0 :gen_fsm with 2 events before and 2 event after" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end,
      [{ :log, 10 }])
    Process.send(pid, 1)
    assert Base.Sys.set_log(pid, 0) === :ok
    Process.send(pid, 2)
    assert Base.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats with 0 events" do
    ref1 = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :stats, true }] }])
    stats = Base.Sys.get_stats(pid)
    assert stats[:in] === 0
    assert stats[:out] === 0
    assert is_integer(stats[:reductions])
    assert stats[:start_time] <= stats[:current_time]
    assert Map.size(stats) === 5
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats with no stats" do
    ref = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref end)
    assert Base.Sys.get_stats(pid) === nil
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats with cast message in" do
    ref1 = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :stats, true }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :in, :hello } }, 500)
    stats = Base.Sys.get_stats(pid)
    assert stats[:in] === 1
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats with call message in" do
    ref1 = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :stats, true }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :in, :hello, self() } }, 500)
    stats = Base.Sys.get_stats(pid)
    assert stats[:in] === 1
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats with message out" do
    ref1 = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :stats, true }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :out, :hello, self() } }, 500)
    stats = Base.Sys.get_stats(pid)
    assert stats[:out] === 1
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats :gen_server with no stats" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    assert Base.Sys.get_stats(pid) === nil
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats :gen_server with 1 message in" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end, [:statistics])
    Process.send(pid, 1)
    stats = Base.Sys.get_stats(pid)
    assert stats[:in] === 1
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats :gen_event with no stats" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    assert Base.Sys.get_stats(pid) === nil
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats :gen_fsm with no stats" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    assert Base.Sys.get_stats(pid) === nil
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats :gen_fsm with 1 message in" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref}  end,
      [:statistics])
    Process.send(pid, 1)
    stats = Base.Sys.get_stats(pid)
    assert stats[:in] === 1
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "print_stats with one of each event" do
    ref1 = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :stats, true }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :in, :hello } }, 500)
    :ok = Base.call(pid, __MODULE__, { :event, { :in, :hello, self() } }, 500)
    :ok = Base.call(pid, __MODULE__, { :event, { :out, :hello, self() } }, 500)
    assert Base.Sys.print_stats(pid) === :ok
    assert close(pid) === :ok
    output = TestIO.binread()
    pattern = "\\A\\*\\* Base.Debug #{inspect(pid)} statistics:\n" <>
    "   Start Time: \\d\\d\\d\\d-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\d\n" <>
    "   Current Time: \\d\\d\\d\\d-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\d\n" <>
    "   Messages In: 2\n" <>
    "   Messages Out: 1\n" <>
    "   Reductions: \\d+\n" <>
    "\n\\z"
    regex = Regex.compile!(pattern)
    assert Regex.match?(regex, output),
      "#{inspect(regex)} not found in #{output}"
  end

  test "print_stats with no stats" do
    ref1 = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref1 end)
    assert Base.Sys.print_stats(pid) === :ok
    assert close(pid) === :ok
    report = "** Base.Debug #{inspect(pid)} statistics not active\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "set_stats true with a cast message in" do
    ref1 = make_ref()
    pid = Base.spawn_link(__MODULE__, fn() -> ref1 end)
    assert Base.Sys.set_stats(pid, true) === :ok
    :ok = Base.call(pid, __MODULE__, { :event, { :in, :hello } }, 500)
    stats = Base.Sys.get_stats(pid)
    assert stats[:in] === 1
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_stats false after a cast message in" do
    ref1 = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :stats, true }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :in, :hello } }, 500)
    assert Base.Sys.set_stats(pid, false) === :ok
    assert Base.Sys.get_stats(pid) === nil
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "log_file" do
    ref1 = make_ref()
    file = Path.join(__DIR__, "logfile")
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :log_file, file }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    assert Base.Sys.set_log_file(pid, nil) === :ok
    log = "** Base.Debug #{inspect(pid)} #{inspect({ :event, 1 })}\n"
    assert File.read!(file) === log
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert Base.Sys.set_log_file(pid, file) === :ok
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 3 } }, 500)
    assert close(pid) === :ok
    log = "** Base.Debug #{inspect(pid)} #{inspect({ :event, 3 })}\n"
    assert File.read!(file) === log
    assert TestIO.binread() === <<>>
  end

  test "log_file bad file" do
    ref1 = make_ref()
    file = Path.join(Path.join(__DIR__, "baddir"), "logfile")
    pid = Base.spawn_link( __MODULE__, fn() -> ref1 end)
    assert_raise ArgumentError, "could not open file: #{inspect(file)}",
      fn() -> Base.Sys.set_log_file(pid, file) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "trace" do
    ref1 = make_ref()
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
    [{ :debug, [{ :trace, true }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    assert Base.Sys.set_trace(pid, false) === :ok
    report1 = "** Base.Debug #{inspect(pid)} #{inspect({ :event, 1 })}\n"
    assert TestIO.binread() === report1
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert TestIO.binread() === report1
    assert Base.Sys.set_trace(pid, true) === :ok
    :ok = Base.call(pid, __MODULE__, { :event, { :in, :hello, self() } }, 500)
    assert close(pid) === :ok
    report2 =  "** Base.Debug #{inspect(pid)} " <>
    "message in (from #{inspect(self())}): :hello\n"
    assert TestIO.binread() === "#{report1}#{report2}"
  end

  test "hook" do
    ref1 = make_ref()
    hook = fn(to, event, process) -> Process.send(to, { process, event }) end
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :hook, { hook, self() } }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    assert_received { ^pid, { :event, 1 } }, "hook did not send message"
    assert Base.Sys.set_hook(pid, hook, nil) === :ok
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    refute_received { ^pid, { :event, 2 } },
      "set_hook nil did not stop hook"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "hook set_hook changes hook state" do
    ref1 = make_ref()
    hook = fn(to, event, process) -> Process.send(to, { process, event }) end
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :hook, { hook, self() } }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    assert_received { ^pid, { :event, 1 } }, "hook did not send message"
    assert Base.Sys.set_hook(pid, hook, pid)
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    refute_received { ^pid, { :event, 2 } },
      "strt_hook did not change hook state"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "hook raises" do
    ref1 = make_ref()
    hook = fn(_to, :raise, _process) ->
      raise(ArgumentError, [])
      (to, event, process) ->
        Process.send(to, { process, event })
    end
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :hook, { hook, self() } }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    assert_received { ^pid, { :event, 1 } }, "hook did not send message"
    :ok = Base.call(pid, __MODULE__, { :event, :raise }, 500)
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    refute_received { ^pid, { :event, 2 } }, "hook raise did not stop it"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "hook done" do
    ref1 = make_ref()
    hook = fn(_to, :done, _process) ->
      :done
      (to, event, process) ->
        Process.send(to, { process, event })
    end
    pid = Base.spawn_link(nil, __MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :hook, { hook, self() } }] }])
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    assert_received { ^pid, { :event, 1 } }, "hook did not send message"
    :ok = Base.call(pid, __MODULE__, { :event, :done }, 500)
    :ok = Base.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    refute_received { ^pid, { :event, 2 } }, "hook done did not stop it"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  # 1 sucess and X failures of get_state, replace_state, change_data,
  # get_data for each gen_event, gen_server, gen_fsm.

  # 1 sucess and X failures for :sys for each of non debug ones (and not
  # get/replace state.. yet)

  ## utils

  defp close(pid) do
    Process.unlink(pid)
    ref = Process.monitor(pid)
    Process.exit(pid, :shutdown)
    receive do
      { :DOWN, ^ref, _, _, :shutdown } ->
        :ok
    after
      500 ->
        Process.demonitor(ref, [:flush])
        Process.link(pid)
        :timeout
    end
  end

  defp inspect_erl(term) do
    :io_lib.format('~p', [term])
      |> List.flatten()
      |> String.from_char_list!()
  end

end