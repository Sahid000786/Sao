defmodule SSHKit do
  @moduledoc """
  A toolkit for performing tasks on one or more servers.

  ```
  hosts = ["1.eg.io", {"2.eg.io", port: 2222}]
  hosts = [%SSHKit.Host{name: "3.eg.io", options: [port: 2223]} | hosts]

  context =
    SSHKit.context(hosts)
    |> SSHKit.path("/var/www/phx")
    |> SSHKit.user("deploy")
    |> SSHKit.group("deploy")
    |> SSHKit.umask("022")
    |> SSHKit.env(%{"NODE_ENV" => "production"})

  :ok = SSHKit.upload(context, ".", recursive: true)
  :ok = SSHKit.run(context, "yarn install", mode: :parallel)
  ```
  """

  alias SSHKit.SSH

  alias SSHKit.Context
  alias SSHKit.Host

  @doc """
  Produces an `SSHKit.Host` struct holding the information
  needed to connect to a (remote) host.

  ## Examples

  You can pass a map with hostname and options:

  ```
  host = SSHKit.host(%{name: "name.io", options: [port: 2222]})

  # This means, that if you pass in a host struct,
  # you'll get the same result. In particular:
  host == SSHKit.host(host)
  ```

  …or, alternatively, a tuple with hostname and options:

  ```
  host = SSHKit.host({"name.io", port: 2222})
  ```

  See `host/2` for additional details and examples.
  """
  def host(%{name: name, options: options}) do
    %Host{name: name, options: options}
  end

  def host({name, options}) do
    %Host{name: name, options: options}
  end

  @doc """
  Produces an `SSHKit.Host` struct holding the information
  needed to connect to a (remote) host.

  ## Examples

  In its most basic version, you just pass a hostname and all other options
  will use the defaults:

  ```
  host = SSHKit.host("name.io")
  ```

  If you wish to provide additional host options, e.g. a non-standard port,
  you can pass a keyword list as the second argument:

  ```
  host = SSHKit.host("name.io", port: 2222)
  ```

  One or many of these hosts can then be used to create an execution context
  in which commands can be executed:

  ```
  host
  |> SSHKit.context()
  |> SSHKit.run("echo \"That was fun\"")
  ```

  See `host/1` for additional ways of specifying host details.
  """
  def host(host, options \\ [])
  def host(name, options) when is_binary(name) do
    %Host{name: name, options: options}
  end

  def host(%{name: name, options: options}, shared_options) do
    %Host{name: name, options: Keyword.merge(shared_options, options)}
  end

  def host({name, options}, shared_options) do
    %Host{name: name, options: Keyword.merge(shared_options, options)}
  end

  @doc """
  Takes one or more (remote) hosts and creates an execution context in which
  remote commands can be run. Accepts any form of host specification also
  accepted by `host/1` and `host/2`, i.e. binaries, maps and 2-tuples.

  See `path/2`, `user/2`, `group/2`, `umask/2`, and `env/2`
  for details on how to derive variations of a context.

  ## Example

  Create an execution context for two hosts. Commands issued in this context
  will be executed on both hosts.

  ```
  hosts = ["10.0.0.1", "10.0.0.2"]
  context = SSHKit.context(hosts)
  ```

  Create a context for hosts with different connection options:

  ```
  hosts = [{"10.0.0.3", port: 2223}, %{name: "10.0.0.4", options: [port: 2224]}]
  context = SSHKit.context(hosts)
  ```

  Any shared options can be specified in the second argument.
  Here we add a user and port for all hosts.

  ```
  hosts = ["10.0.0.1", "10.0.0.2"]
  options = [user: "admin", port: "2222"]
  context = SSHKit.context(hosts, options)
  ```
  """

  def context(hosts, shared_options \\ []) do
    hosts =
      hosts
      |> List.wrap()
      |> build_hosts(shared_options)
    %Context{hosts: hosts}
  end

  @doc """
  Changes the working directory commands are executed in for the given context.

  Returns a new, derived context for easy chaining.

  ## Example

  Create `/var/www/app/config.json`:

  ```
  "10.0.0.1"
  |> SSHKit.context()
  |> SSHKit.path("/var/www/app")
  |> SSHKit.run("touch config.json")
  ```
  """
  def path(context, path) do
    %Context{context | path: path}
  end

  @doc """
  Changes the file creation mode mask affecting default file and directory
  permissions.

  Returns a new, derived context for easy chaining.

  ## Example

  Create `precious.txt`, readable and writable only for the logged-in user:

  ```
  "10.0.0.1"
  |> SSHKit.context()
  |> SSHKit.umask("077")
  |> SSHKit.run("touch precious.txt")
  ```
  """
  def umask(context, mask) do
    %Context{context | umask: mask}
  end

  @doc """
  Specifies the user under whose name commands are executed.
  That user might be different than the user with which
  ssh connects to the remote host.

  Returns a new, derived context for easy chaining.

  ## Example

  All commands executed in the created `context` will run as `deploy_user`,
  although we use the `login_user` to log in to the remote host:

  ```
  context =
    {"10.0.0.1", port: 3000, user: "login_user", password: "secret"}
    |> SSHKit.context()
    |> SSHKit.user("deploy_user")
  ```
  """
  def user(context, name) do
    %Context{context | user: name}
  end

  @doc """
  Specifies the group commands are executed with.

  Returns a new, derived context for easy chaining.

  ## Example

  All commands executed in the created `context` will run in group `www`:

  ```
  context =
    "10.0.0.1"
    |> SSHKit.context()
    |> SSHKit.group("www")
  ```
  """
  def group(context, name) do
    %Context{context | group: name}
  end

  @doc """
  Defines new environment variables or overrides existing ones
  for a given context.

  Returns a new, derived context for easy chaining.

  ## Examples

  Setting `NODE_ENV=production`:

  ```
  context =
    "10.0.0.1"
    |> SSHKit.context()
    |> SSHKit.env(%{"NODE_ENV" => "production"})

  # Run the npm start script with NODE_ENV=production
  SSHKit.run(context, "npm start")
  ```

  Modifying the `PATH`:

  ```
  context =
    "10.0.0.1"
    |> SSHKit.context()
    |> SSHKit.env(%{"PATH" => "$HOME/.rbenv/shims:$PATH"})

  # Execute the rbenv-installed ruby to print its version
  SSHKit.run(context, "ruby --version")
  ```
  """
  def env(context, map) do
    %Context{context | env: map}
  end

  @doc ~S"""
  Executes a command in the given context.

  Returns a list of tuples, one fore each host in the context.

  The resulting tuples have the form `{:ok, output, exit_code}` –
  as returned by `SSHKit.SSH.run/3`:

  * `exit_code` is the number with which the executed command returned.

      If everything went well, that usually is `0`.

  * `output` is a keyword list of the output collected from the command.

      It has the form:

      ```
      [
        stdout: "output on standard out",
        stderr: "output on standard error",
        stdout: "some more normal output",
        …
      ]
      ```

  ## Example

  Run a command and verify its output:

  ```
  [{:ok, output, 0}] =
    "my.remote-host.tld"
    |> SSHKit.context()
    |> SSHKit.run("echo \"Hello World!\"")

  stdout =
    output
    |> Keyword.get_values(:stdout)
    |> Enum.join()

  assert "Hello World!\n" == stdout
  ```
  """
  def run(context, command) do
    cmd = Context.build(context, command)

    run = fn host ->
      {:ok, conn} = SSH.connect(host.name, host.options)
      res = SSH.run(conn, cmd)
      :ok = SSH.close(conn)
      res
    end

    Enum.map(context.hosts, run)
  end

  # def upload(context, path, options \\ []) do
  #   …
  #   # resolve remote relative to context path
  #   remote = Path.expand(Map.get(options, :as, Path.basename(path)), _)
  #   SCP.upload(conn, path, remote, options)
  # end

  # def download(context, path, options \\ []) do
  #   …
  #   remote = _ # resolve remote relative to context path
  #   local = Map.get(options, :as, Path.basename(path))
  #   SCP.download(conn, remote, local, options)
  # end

  defp build_hosts(hosts, shared_options) do
    build_host = &host(&1, shared_options)
    Enum.map(hosts, build_host)
  end
end
