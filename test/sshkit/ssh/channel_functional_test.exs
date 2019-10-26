defmodule SSHKit.SSH.ChannelFunctionalTest do
  @moduledoc false

  use SSHKit.FunctionalCase, async: true

  @bootconf [user: "me", password: "pass"]

  describe "Channel.subsystem/3" do
    @tag boot: [@bootconf]
    test "with user", %{hosts: [host]} do
      {:ok, conn} = SSHKit.SSH.connect(host.name, host.options)
      {:ok, channel} = SSHKit.SSH.Channel.open(conn)
      :success = SSHKit.SSH.Channel.subsystem(channel, "greeting-subsystem")

      assert readline(channel) == "Hello, who am I talking to?\n"

      SSHKit.SSH.Channel.send(channel, "Lorem\n")

      assert readline(channel) == "It's nice to meet you Lorem\n"
    end
  end

  defp readline(channel, message \\ "") do
    {:ok, {:data, _channel, _type, next_line}} = SSHKit.SSH.Channel.recv(channel)

    if String.ends_with?(next_line, "\n") do
      "#{message}#{next_line}"
    else
      readline(channel, "#{message}#{next_line}")
    end
  end
end
