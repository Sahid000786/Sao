defmodule SSHKitFunctionalTest do
  @moduledoc false

  use SSHKit.FunctionalCase, async: true

  @bootconf [user: "me", password: "pass"]

  describe "run/2" do
    @tag boot: [@bootconf]
    test "connects as the login user and runs commands", %{hosts: [host]} do
      [{:ok, output, 0}] =
        host
        |> SSHKit.context()
        |> SSHKit.run("id -un")

      name = String.trim(stdout(output))
      assert name == host.options[:user]
    end

    @tag boot: [@bootconf]
    test "runs commands and returns their output and exit status", %{hosts: [host]} do
      context = SSHKit.context(host)

      [{:ok, output, status}] = SSHKit.run(context, "pwd")
      assert status == 0
      assert stdout(output) == "/home/me\n"

      [{:ok, output, status}] = SSHKit.run(context, "ls non-existing")
      assert status == 1
      assert stderr(output) =~ "ls: non-existing: No such file or directory"

      [{:ok, output, status}] = SSHKit.run(context, "does-not-exist")
      assert status == 127
      assert stderr(output) =~ "'does-not-exist': No such file or directory"
    end

    @tag boot: [@bootconf]
    test "with env", %{hosts: [host]} do
      [{:ok, output, status}] =
        host
        |> SSHKit.context()
        |> SSHKit.env(%{"PATH" => "$HOME/.rbenv/shims:$PATH", "NODE_ENV" => "production"})
        |> SSHKit.run("env")

      assert status == 0

      output = stdout(output)
      assert output =~ "NODE_ENV=production"
      assert output =~ ~r/PATH=.*\/\.rbenv\/shims:/
    end

    @tag boot: [@bootconf]
    test "with umask", %{hosts: [host]} do
      context =
        host
        |> SSHKit.context()
        |> SSHKit.umask("077")

      [{:ok, _, 0}] = SSHKit.run(context, "mkdir my_dir")
      [{:ok, _, 0}] = SSHKit.run(context, "touch my_file")

      [{:ok, output, status}] = SSHKit.run(context, "ls -la")

      assert status == 0

      output = stdout(output)
      assert output =~ ~r/drwx--S---\s+2\s+me\s+me\s+4096.+my_dir/
      assert output =~ ~r/-rw-------\s+1\s+me\s+me\s+0.+my_file/
    end

    @tag boot: [@bootconf]
    test "with path", %{hosts: [host]} do
      context =
        host
        |> SSHKit.context()
        |> SSHKit.path("/var/log")

      [{:ok, output, status}] = SSHKit.run(context, "pwd")

      assert status == 0
      assert stdout(output) == "/var/log\n"
    end

    @tag boot: [@bootconf]
    test "with user", %{hosts: [host]} do
      add_user_to_group!(host, host.options[:user], "passwordless-sudoers")

      adduser!(host, "despicable_me")

      context =
        host
        |> SSHKit.context()
        |> SSHKit.user("despicable_me")

      [{:ok, output, status}] = SSHKit.run(context, "id -un")

      assert status == 0
      assert stdout(output) == "despicable_me\n"
    end

    @tag boot: [@bootconf]
    test "with group", %{hosts: [host]} do
      add_user_to_group!(host, host.options[:user], "passwordless-sudoers")

      adduser!(host, "gru")
      addgroup!(host, "villains")
      add_user_to_group!(host, "gru", "villains")

      context =
        host
        |> SSHKit.context()
        |> SSHKit.user("gru")
        |> SSHKit.group("villains")

      [{:ok, output, status}] = SSHKit.run(context, "id -gn")

      assert status == 0
      assert stdout(output) == "villains\n"
    end
  end

  describe "upload/3" do
    @tag boot: [@bootconf, @bootconf]
    test "uploads a file", %{hosts: hosts} do
      local = "test/fixtures/local.txt"

      context = SSHKit.context(hosts)

      assert [:ok, :ok] = SSHKit.upload(context, local)
      assert verify_transfer(context, local, Path.basename(local))
    end

    @tag boot: [@bootconf, @bootconf]
    test "recursive: true", %{hosts: [host | _] = hosts} do
      local = "test/fixtures"
      remote = "/home/#{host.options[:user]}/fixtures"

      context = SSHKit.context(hosts)

      assert [:ok, :ok] = SSHKit.upload(context, local, recursive: true)
      assert verify_transfer(context, local, remote)
    end

    @tag boot: [@bootconf, @bootconf]
    test "preserve: true", %{hosts: hosts} do
      local = "test/fixtures/local.txt"
      remote = Path.basename(local)

      context = SSHKit.context(hosts)

      assert [:ok, :ok] = SSHKit.upload(context, local, preserve: true)
      assert verify_transfer(context, local, remote)
      assert verify_mode(context, local, remote)
      assert verify_mtime(context, local, remote)
    end

    @tag boot: [@bootconf, @bootconf]
    test "recursive: true, preserve: true", %{hosts: [host | _] = hosts} do
      local = "test/fixtures"
      remote = "/home/#{host.options[:user]}/fixtures"

      context = SSHKit.context(hosts)

      assert [:ok, :ok] = SSHKit.upload(context, local, recursive: true, preserve: true)
      assert verify_transfer(context, local, remote)
      assert verify_mode(context, local, remote)
      assert verify_mtime(context, local, remote)
    end
  end

  describe "download/3" do
    setup do
      tmpdir = create_local_tmp_path()

      :ok = File.mkdir!(tmpdir)
      on_exit fn -> File.rm_rf(tmpdir) end

      {:ok, tmpdir: tmpdir}
    end

    @tag boot: [@bootconf]
    test "gets a file", %{hosts: hosts, tmpdir: tmpdir} do
      remote = "/fixtures/remote.txt"
      local = Path.join(tmpdir, Path.basename(remote))

      context = SSHKit.context(hosts)

      assert [:ok] = SSHKit.download(context, remote, as: local)
      assert verify_transfer(context, local, remote)
    end

    @tag boot: [@bootconf]
    test "recursive: true", %{hosts: hosts, tmpdir: tmpdir} do
      remote = "/fixtures"
      local = Path.join(tmpdir, "fixtures")

      context = SSHKit.context(hosts)

      assert [:ok] = SSHKit.download(context, remote, recursive: true, as: local)
      assert verify_transfer(context, local, remote)
    end

    @tag boot: [@bootconf]
    test "preserve: true", %{hosts: hosts, tmpdir: tmpdir} do
      remote = "/fixtures/remote.txt"
      local = Path.join(tmpdir, Path.basename(remote))

      context = SSHKit.context(hosts)

      assert [:ok] = SSHKit.download(context, remote, preserve: true, as: local)
      assert verify_mode(context, local, remote)
      assert verify_atime(context, local, remote)
      assert verify_mtime(context, local, remote)
    end

    @tag boot: [@bootconf]
    test "recursive: true, preserve: true", %{hosts: hosts, tmpdir: tmpdir} do
      remote = "/fixtures"
      local = Path.join(tmpdir, "fixtures")

      context = SSHKit.context(hosts)

      assert [:ok] = SSHKit.download(context, remote, recursive: true, preserve: true, as: local)
      assert verify_mode(context, local, remote)
      assert verify_atime(context, local, remote)
      assert verify_mtime(context, local, remote)
    end
  end

  defp stdio(output, type) do
    output
    |> Keyword.get_values(type)
    |> Enum.join()
  end

  def stdout(output), do: stdio(output, :stdout)
  def stderr(output), do: stdio(output, :stderr)
end
