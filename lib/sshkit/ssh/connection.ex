defmodule SSHKit.SSH.Connection do
  @moduledoc """
  Defines a `SSHKit.SSH.Connection` struct representing a host connection.

  A connection struct has the following fields:

  * `host` - the name or IP of the remote host
  * `port` - the port to connect to
  * `options` - additional connection options
  * `ref` - the underlying `:ssh` connection ref
  """

  alias SSHKit.SSH.Connection
  alias SSHKit.Utils

  defstruct [:host, :port, :options, :ref, :ssh_modules]

  @ssh_modules %{ssh: :ssh, ssh_connection: :ssh_connection}

  @doc """
  Opens a connection to an SSH server.

  A timeout in ms can be provided through the `:timeout` option.
  The default value is `:infinity`.

  A few more, common options are `:port`, `:user` and `:password`.
  Port defaults to `22`, user to `$LOGNAME` or `$USER` on UNIX,
  `$USERNAME` on Windows.

  The `:user_interaction` option is set to false by default.

  For a complete list of options and their default values, see:
  [`:ssh.connect/4`](http://erlang.org/doc/man/ssh.html#connect-4).

  Returns `{:ok, conn}` on success, `{:error, reason}` otherwise.
  """
  def open(host, options \\ [])
  def open(nil, _) do
    {:error, "No host given."}
  end
  def open(host, options) when is_binary(host) do
    open(to_charlist(host), options)
  end
  def open(host, options) do
    port = Keyword.get(options, :port, 22)
    timeout = Keyword.get(options, :timeout, :infinity)
    ssh_modules = Keyword.get(options, :ssh_modules, @ssh_modules)
    ssh = erlang_module(%{ssh_modules: ssh_modules}, :ssh)

    defaults = [user_interaction: false]

    options =
      defaults
      |> Keyword.merge(options)
      |> Keyword.drop([:port, :timeout, :ssh_modules])
      |> Utils.charlistify()

    case ssh.connect(host, port, options, timeout) do
      {:ok, ref} -> {:ok, %Connection{host: host, port: port, options: options, ref: ref, ssh_modules: ssh_modules}}
      err -> err
    end
  end

  defp erlang_module(conn, name) do
    Map.fetch!(conn.ssh_modules, name)
  end

  @doc """
  Closes an SSH connection.

  Returns `:ok`.

  For details, see [`:ssh.close/1`](http://erlang.org/doc/man/ssh.html#close-1).
  """
  def close(conn) do
    ssh = erlang_module(conn, :ssh)
    ssh.close(conn.ref)
  end

  @doc """
  Opens a new connection, based on the parameters of an existing one.

  The timeout value of the original connection is discarded.
  Other connection options are reused and may be overridden.

  Uses `SSHKit.SSH.open/2`.

  Returns `{:ok, conn}` or `{:error, reason}`.
  """
  def reopen(connection, options \\ []) do
    options =
      connection.options
      |> Keyword.put(:port, connection.port)
      |> Keyword.merge(options)

    open(connection.host, options)
  end
end
