defmodule Archethic.Utils.Regression.Benchmark.SeedHolder do
  @moduledoc """
  A GenServer managing a pool of cryptographic seeds for benchmark tests.

  This process holds a collection of seeds (random binary data used to derive keys)
  and allows benchmark workers to safely and concurrently:
  - Retrieve the list of all seeds (`get_seeds/1`).
  - Get a random seed (`get_random_seed/1`).
  - Atomically pop a seed from the pool (`pop_seed/1`), ensuring it's not used by
    another worker simultaneously. This also returns an index/counter associated
    with the seed.
  - Put a previously popped seed back into the pool (`put_seed/3`), incrementing its index.

  The state is a map where keys are the seeds (binaries) and values are counters
  (integers, representing how many times a seed has been used or its original index).
  """
  use GenServer

  @vsn 1

  @doc """
  Starts the SeedHolder GenServer.

  Accepts an `opts` keyword list which must contain the `:seeds` key
  with a list of binary seeds to initialize the pool.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  @doc """
  Initializes the GenServer state.

  Takes the `:seeds` list from the arguments and transforms it into a map
  where each seed is a key and the initial value (counter) is 0.
  """
  def init(args) do
    seeds = Keyword.fetch!(args, :seeds)
    state = Map.new(seeds, fn seed -> {seed, 0} end)
    {:ok, state}
  end

  @doc """
  Retrieves all seeds currently held by the SeedHolder.

  This is a synchronous call.
  """
  def get_seeds(pid) do
    GenServer.call(pid, :get_seeds)
  end

  @doc """
  Retrieves a random seed from the pool without removing it.

  This is a synchronous call.
  """
  def get_random_seed(pid) do
    GenServer.call(pid, :get_random_seed)
  end

  @doc """
  Atomically removes and returns a random seed and its associated counter/index
  from the pool.

  This ensures that parallel benchmark workers do not attempt to use the
  same seed concurrently for operations that require exclusive use (like sending
  a transaction from an address derived from the seed).

  This is a synchronous call.
  """
  def pop_seed(pid) do
    GenServer.call(pid, :pop)
  end

  # --- GenServer Callbacks ---

  @impl GenServer
  # Handles the :get_seeds call. Replies with the list of seeds (map keys).
  def handle_call(:get_seeds, _from, state) do
    {:reply, Map.keys(state), state}
  end

  @impl GenServer
  # Handles the :pop call. Selects a random seed, removes it from the state map,
  # and replies with the seed and its associated value (index/counter).
  def handle_call(:pop, _from, state) do
    seeds_list = Map.keys(state)
    seed = Enum.random(seeds_list)
    {index, new_state} = Map.pop(state, seed)

    {:reply, {seed, index}, new_state}
  end

  @impl GenServer
  # Handles the :get_random_seed call. Selects a random seed but does not modify the state.
  def handle_call(:get_random_seed, _from, state) do
    seed_list = Map.keys(state)
    seed = Enum.random(seed_list)
    {:reply, seed, state}
  end

  @doc """
  Asynchronously puts a seed back into the pool, incrementing its counter.

  Typically called after a benchmark worker has finished using a popped seed.
  Uses `cast` for an asynchronous operation as no reply is needed.
  """
  def put_seed(pid, seed, index) do
    GenServer.cast(pid, {:put, seed, index})
  end

  @impl GenServer
  # Handles the asynchronous :put cast. Re-inserts the seed into the state map,
  # incrementing its associated counter.
  def handle_cast({:put, seed, index}, state) do
    {:noreply, Map.put(state, seed, index + 1)}
  end
end
