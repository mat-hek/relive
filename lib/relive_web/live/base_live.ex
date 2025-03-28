defmodule ReliveWeb.BaseLive do
  use ReliveWeb, :live_view

  alias Relive.Audio.Pipeline
  alias Relive.Audio.Supervisor

  @impl true
  def mount(_, _, socket) do
    socket =
      socket
      |> change_pipeline(:default)

    if connected?(socket) do
      Relive.subscribe_amplitude()
      Relive.subscribe_speech()
      Relive.subscribe_assistant()

      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_info({:amp, element, amp}, socket) do
    socket =
      socket
      |> assign(:last_amp, Map.put(socket.assigns.last_amp, element, amp))

    socket =
      case element do
        :peak_1 ->
          assign(socket, :waveform, Enum.take([amp | socket.assigns.waveform], 100))

        _ ->
          socket
      end

    {:noreply, socket}
  end

  def handle_info({:speaking, event, _prob}, socket) do
    status =
      case event do
        :start ->
          :speaking

        :stop ->
          :not_speaking
      end

    socket =
      socket
      |> assign(:status, status)

    {:noreply, socket}
  end

  def handle_info({:transcript, text}, socket) do
    socket =
      socket
      |> assign(:latest_transcript, text)

    {:noreply, socket}
  end

  def handle_info({:chunks, exchange}, socket) do
    socket =
      socket
      |> assign(:exchange, Enum.reverse(exchange))

    {:noreply, socket}
  end

  @impl true
  def handle_event("switch-pipeline", %{"variant" => variant_str}, socket) do
    variant =
      variant_str
      |> String.downcase()
      |> String.to_existing_atom()

    {:noreply, change_pipeline(socket, variant)}
  end

  defp change_pipeline(socket, variant) do
    Relive.switch_audio(variant)
    opts = Supervisor.opts_from_variant(variant)

    children =
      variant
      |> Pipeline.children(opts)
      |> then(& &1.children)
      |> Enum.map(fn child ->
        label = elem(child, 0)
        spec = elem(child, 1)

        {type, struct} =
          case spec do
            spec when is_struct(spec) ->
              {spec.__struct__, Map.from_struct(spec)}

            spec when is_atom(spec) ->
              try do
                {spec, struct(spec) |> Map.from_struct()}
              rescue
                _ -> {:unknown, %{}}
              end
          end

        struct =
          struct
          |> Enum.filter(fn {_key, value} ->
            is_integer(value) or is_float(value) or is_binary(value)
          end)
          |> Map.new()

        type =
          type
          |> to_string()
          |> String.replace("Elixir.", "")
          |> String.replace("Membrane.", "")
          |> String.replace("Relive.Audio.", "")

        %{label: label, spec: struct, type: type}
      end)

    socket
    |> assign(:last_amp, %{})
    |> assign(:waveform, [])
    |> assign(:status, :not_speaking)
    |> assign(:variants, Pipeline.variants())
    |> assign(:exchange, [])
    |> assign(:latest_transcript, nil)
    |> assign(:variant, variant)
    |> assign(
      :children,
      children
    )
    |> assign(:exchange, [])
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="peaks-1" class="absolute top-0 left-0 w-screen z-10">
      <div
        :for={amp <- @waveform}
        class="bg-sky-600 h-[1vh]"
        style={"transform: scale(#{amp_percent(amp)}, 1.0)"}
      >
      </div>
    </div>

    <div
      id="speaks"
      class={"absolute top-0 left-0 w-screen h-full z-8 pointer-events-none transition " <> if @status == :speaking do "opacity-100" else "opacity-0" end}
      style="background-image: radial-gradient(rgba(0,255,170,0.0) 50%, rgba(0,255,170,0.5) 100%);"
    >
    </div>

    <div class="relative" style="z-index: 100;">
      <form id="variants" phx-change="switch-pipeline" class="m-4 bg-slate-800 rounded-md px-2 py-2">
        <label class="text-sm text-slate-200">
          Pipeline:
          <select
            id="variant"
            name="variant"
            class="mx-2 border-0 rounded-md text-sm bg-slate-600 text-slate-100"
          >
            <option
              :for={variant <- @variants}
              selected={variant == @variant}
              value={to_string(variant)}
            >
              {String.replace(String.capitalize(to_string(variant)), "_", " ")}
            </option>
          </select>
        </label>
      </form>
      <div class="flex gap-4 text-sm p-4">
        <form
          :for={child <- @children |> Enum.reverse()}
          class="bg-slate-600 rounded-md px-2 py-1 grow"
        >
          <h2 class="mb-2 text-slate-200">
            {child.label}
            <div class="text-slate-200">
              {child.type}
            </div>
          </h2>
          <ul class="text-slate-300">
            <li :for={{key, value} <- child.spec}>
              <div>{key}</div>
              <div>{value}</div>
            </li>
          </ul>
        </form>
      </div>
    </div>

    <div class="mx-12 my-4 absolute bottom-0 z-20 flex flex-wrap overflow-hidden">
      <div
        :for={{party, text} <- @exchange}
        :if={party != :system}
        class={"w-1/2 rounded-lg mb-16 p-2 " <> if party == :user do "bg-emerald-200 text-emerald-900 pr-12 " else "-translate-x-8 translate-y-12 bg-purple-200 text-purple-900" end}
      >
        <span class={"block " <> if party == :user do "text-emerald-700" else "text-purple-700" end}>
          {party}
        </span>
        <span class="">{text}</span>
      </div>
      <div
        :if={assigns[:latest_transcript]}
        class="w-full rounded-lg mb-2 p-2 bg-sky-200 text-teal-900 pr-12"
      >
        <span class="block text-teal-700">latest transcript</span>
        <span class="">{assigns[:latest_transcript]}</span>
      </div>
    </div>
    """
  end

  defp amp_percent(amp) do
    Float.round((amp + 70) / 70, 2)
  end
end
