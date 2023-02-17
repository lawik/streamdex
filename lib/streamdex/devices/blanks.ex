defmodule Streamdex.Devices.Blanks do
  @path Path.join(Application.app_dir(:streamdex), "priv/blank/")
  @plus File.read!(Path.join(@path, "plus.jpg"))
  def plus, do: @plus
end
