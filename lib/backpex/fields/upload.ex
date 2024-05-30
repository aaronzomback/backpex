defmodule Backpex.Fields.Upload do
  @moduledoc ~S"""
  A field for handling an upload.

  > #### Warning {: .warning}
  >
  > This field is in beta state. Use at your own risk.

  ## Options

    * `:upload_key` (atom) - Required identifier for the upload field (the name of the upload).
    * `:accept` (list) - Required filetypes that will be accepted.
    * `:max_entries` (integer) - Required number of max files that can be uploaded.
    * `:max_file_size` (integer) - Optional maximum file size in bytes to be allowed to uploaded. Defaults 8 MB (`8_000_000`).
    * `:list_existing_files` - Required function that returns a list of all uploaded files based on an item.
    * `:file_label` - Optional function to get the label of a single file.
    * `:consume_upload` - Required function to consume file uploads.
    * `:put_upload_change` - Required function to add file paths to the change.
    * `:remove_uploads` - Required function that is being called after saving an item to be able to delete removed files

  ## Options in detail

  The `upload_key`, `accept`, `max_entries` and `max_file_size` options are forwarded to https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#allow_upload/3. See the documentation for more information.

  ### `list_existing_files`

  **Parameters**
  * `:socket` - The socket.
  * `:item` (struct) - The item without its changes.

  The function is being used to display existing uploads. The function receives the socket and the item and has to return a list of strings. Removed files during an edit of an item are automatically removed from the list. This option is required.

  **Example**

      def list_existing_files(_socket, item), do: item.files

  ### `file_label`

  **Parameters**
  * `:file` (string) - The file.

  The function can be used to modify a file label based on a file. In the following example each file will have an "_upload" suffix. This option is optional.

  **Example**

      def file_label(file), do: file <> "_upload"

  ### `consume_upload`

  **Parameters**
  * `:socket` - The socket.
  * `:meta` - The upload meta.
  * `:entry` - The upload entry.

  The function is used to consume uploads. It is called after the item has been saved and is used to copy the files to a specific destination. Backpex will use this function as a callback for `consume_uploaded_entries`. See https://hexdocs.pm/phoenix_live_view/uploads.html#consume-uploaded-entries for more details. This option is required.

  **Example**

      defp consume_upload(_socket, %{path: path} = _meta, entry) do
        file_name = ...
        file_url = ...
        static_dir = ...
        dest = Path.join([:code.priv_dir(:demo), "static", static_dir, file_name])

        File.cp!(path, dest)

        {:ok, file_url}
      end

  ### `put_upload_change`

  **Parameters**
    * `:socket` - The socket.
    * `:change` (map) - The current change / attrs that will be passed to the changeset function.
    * `:item` (struct) - The item without its changes. On create will this will be an empty map.
    * `uploaded_entries` (tuple) - The completed and in progress entries for the upload.
    * `removed_entries` (list) - A list of removed uploads during edit.
    * `action` (atom) - The action (`:validate` or `:insert`)

  This function is used to modify the change based on certain parameters. It is important because it ensures that file paths are added to the item change and therefore persisted in the database. This option is required.

  **Example**

      def put_upload_change(_socket, change, item, uploaded_entries, removed_entries, action) do
        existing_files = item.files -- removed_entries

        case action do
          :validate ->
            {_completed, in_progress} = uploaded_entries
              Map.put(change, :upload, in_progress ++ existing_files)

          :insert ->
            {completed, _in_progress} = uploaded_entries
            Map.put(change, :upload, completed ++ existing_files)
        end
      end

  ### `remove_uploads`

  **Parameters**
  * `:socket` - The socket.
  * `removed_entries` (list) - A list of removed uploads during edit.

  **Example**

      defp remove_uploads(_socket, removed_entries) do
        for file <- removed_entries do
          file_path = ...
          File.rm!(file_path)
        end
      end

  ## Full Single File Example

  In this example we implement an avatar upload that is attached to a user.

      @impl Backpex.LiveResource
      def fields do
        [
          avatar: %{
            module: Backpex.Fields.Upload,
            label: "Avatar",
            upload_key: :avatar,
            accept: ~w(.jpg .jpeg),
            max_entries: 1,
            max_file_size: 512_000,
            put_upload_change: &put_upload_change/6,
            consume_upload: &consume_upload/3,
            remove_uploads: &remove_uploads/2,
            list_existing_files: fn
              %{avatar: ""} -> []
              %{avatar: avatar} -> [avatar]
            end,
            render: fn
              %{value: value} = assigns when value == "" or is_nil(value) ->
                ~H"<p><%= Backpex.HTML.pretty_value(@value) %></p>"

              assigns ->
                ~H'<img class="h-10 w-auto" src={avatar_file_url(@value)} />'
            end,
            align: :center
          },
        ]

        # Validate (uploads are in progress)
        def put_upload_change(socket, change, item, uploaded_entries, removed_entries, :validate) do
          case {uploaded_entries, removed_entries} do
            # If there is an upload, we want to include it in the change.
            {{[] = _completed, [entry | _] = _in_progress}, _removed} ->
              Map.put(change, "avatar", avatar_file_name(entry))

            # If there is no new upload, but a removed one, we want to reset the avatar.
            {_uploaded, [entry]} ->
              Map.put(change, "avatar", "")

            # If there is no new upload and no removed upload, we want to do nothing.
            _other ->
              change
          end
        end

        # Insert (Uploads are completed)
        def put_upload_change(_socket, change, item, uploaded_entries, removed_entries, :insert) do
          case {uploaded_entries, removed_entries} do
            # If there is an completed upload, we want to include it in the change.
            {{[entry | _] = _completed, _in_progress}, _removed} ->
              Map.put(change, "avatar", avatar_file_name(entry))

            # If there is no completed upload, but a removed one, we want to reset the avatar.
            {_uploaded, [entry]} ->
              Map.put(change, "avatar", "")

            # If there is no completed upload and no removed upload, we want to do nothing.
            _other ->
              change
          end
        end

        defp consume_upload(_socket, %{path: path} = _meta, entry) do
          file_name = avatar_file_name(entry)
          dest = Path.join([:code.priv_dir(:demo), "static", avatar_static_dir(), file_name])

          # Copy the file to the destination
          File.cp!(path, dest)

          {:ok, avatar_file_url(file_name)}
        end

        # Remove all removed entries from disk.
        defp remove_uploads(_socket, removed_entries) do
          for file <- removed_entries do
            file_name = avatar_file_name(entry)
            file_path = Path.join([:code.priv_dir(:demo), "static", avatar_static_dir(), file_name])

            File.rm!(path)
          end
        end

        # Returns the place where we want to store the uploads.
        defp avatar_static_dir, do: Path.join(["uploads", "user", "avatar"])

        # Returns the url based on a file name.
        defp avatar_file_url(file_name) do
          static_path = Path.join([avatar_static_dir(), file_name])
          Phoenix.VerifiedRoutes.static_url(DemoWeb.Endpoint, "/" <> static_path)
        end

        # Returns the name based on an entry.
        defp avatar_file_name(entry) do
          [ext | _] = MIME.extensions(entry.client_type)
          "#{entry.uuid}.#{ext}"
        end

  ## Full Multi File Example

  TODO

  TODO: remove old docs

  ### Multiple Files

      @impl Backpex.LiveResource
      def fields do
      [
        gallery: %{
          module: Backpex.Fields.Upload,
          label: "Gallery",
          upload_key: :gallery,
          accept: ~w(.jpg .jpeg),
          max_entries: 5,
          list_files: &list_files_gallery/2,
          consume: &consume_gallery/3,
          remove: &remove_gallery/3,
        }
      ]
      end

      defp gallery_static_dir, do: Path.join(["uploads", "user", "gallery"])

      defp gallery_file_url(file_name) do
        static_path = Path.join([gallery_static_dir(), file_name])
        Phoenix.VerifiedRoutes.static_url(MyAppWeb.Endpoint, "/" <> static_path)
      end

      defp gallery_file_name(entry) do
        [ext | _] = MIME.extensions(entry.client_type)
        "#{entry.uuid}.#{ext}"
      end

      # will be called to consume uploads
      # you may add completed file upload paths as part of the change in order to persist them
      # you have to return the (modified) change
      def consume_gallery(socket, item, %{} = change) do
        consume_uploaded_entries(socket, :gallery, fn %{path: path}, entry ->
          file_name = gallery_file_name(entry)
          dest = Path.join([:code.priv_dir(:my_app), "static", gallery_static_dir(), file_name])
          File.cp!(path, dest)
          {:ok, gallery_file_url(file_name)}
        end)

        {completed, []} = uploaded_entries(socket, :gallery)

        file_names = Enum.map(completed, fn entry -> gallery_file_name(entry) end)

        file_names =
          case item do
            %{id: id} when is_binary(id) ->
              (Repo.get_by!(Event, id: id) |> Map.get(:gallery)) ++ file_names

            _ ->
              file_names
          end

        Map.put(change, "gallery", file_names)
      end

      # will be called in order to display files when editing item
      def list_files_gallery(%{gallery: gallery}), do: gallery

      # will be called when deleting certain file from existing item
      # target is the key you provided in list/2
      # remove files from file system and item, return new file paths to be displayed
      def remove_gallery(item, target) do
        element = Repo.get_by!(Event, id: item.id)

        file_paths =
          Map.get(element, :gallery)
          |> Enum.reject(&(&1 == target))

        Event.changeset(element, %{gallery: file_paths})
        |> Repo.update!()

        file_paths
      end
  """
  use BackpexWeb, :field

  import Phoenix.LiveView, only: [allow_upload: 3]

  @impl Backpex.Field
  def render_value(assigns) do
    %{field: field, item: item} = assigns

    uploaded_files = existing_file_paths(field, item, [])

    assigns = assign(assigns, :uploaded_files, uploaded_files)

    ~H"""
    <div class="flex flex-col">
      <p :for={{_file_key, label} <- @uploaded_files}>
        <%= label %>
      </p>
    </div>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    upload_key = assigns.field_options.upload_key
    uploads_allowed = not is_nil(assigns.field_uploads)
    form_errors = Backpex.HTML.Form.translate_form_errors(assigns.form[assigns.name], assigns.field_options)

    assigns =
      assigns
      |> assign(:upload_key, upload_key)
      |> assign(:uploads_allowed, uploads_allowed)
      |> assign(:uploaded_files, Keyword.get(assigns.uploaded_files, upload_key))
      |> assign(:form_errors, form_errors)

    ~H"""
    <div x-data="{
        dispatchChangeEvent(el) {
          $nextTick(
            () => {
              form = document.getElementById('resource-form');
              if (form) el.dispatchEvent(new Event('input', { bubbles: true }));
            }
          )
        }
      }">
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns, :top)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <div
          x-data="{dragging: 0}"
          x-on:dragenter="dragging++"
          x-on:dragleave="dragging--"
          x-on:drop="dragging = 0"
          class="w-full max-w-lg"
          phx-drop-target={if @uploads_allowed, do: @field_uploads.ref}
        >
          <div
            class="flex justify-center rounded-md border-2 border-dashed px-6 pt-5 pb-6"
            x-bind:class="dragging > 0 ? 'border-primary' : 'border-content'"
          >
            <div class="flex flex-col items-center space-y-1 text-center">
              <Heroicons.document_arrow_up class="h-8 w-8 text-gray-400" />
              <div class="flex text-sm">
                <label>
                  <a class="link link-hover link-primary font-medium">
                    <%= Backpex.translate("Upload a file") %>
                  </a>
                  <.live_file_input
                    :if={@uploads_allowed}
                    upload={@field_uploads}
                    phx-target="#form-component"
                    class="hidden"
                  />
                </label>
                <p class="pl-1"><%= Backpex.translate("or drag and drop") %></p>
              </div>
            </div>
          </div>
        </div>

        <section class="mt-2">
          <article>
            <%= if @uploads_allowed do %>
              <div :for={entry <- @field_uploads.entries}>
                <p class="inline"><%= Map.get(entry, :client_name) %></p>

                <button
                  type="button"
                  phx-click="cancel-entry"
                  phx-value-ref={entry.ref}
                  phx-value-id={@upload_key}
                  phx-target="#form-component"
                  @click="() => dispatchChangeEvent($el)"
                >
                  &times;
                </button>

                <p :for={err <- upload_errors(@field_uploads, entry)} class="text-xs italic text-red-500">
                  <%= error_to_string(err) %>
                </p>
              </div>
            <% end %>

            <%= if @type == :form do %>
              <div :for={{file_key, label} <- @uploaded_files}>
                <p class="inline"><%= label %></p>
                <button
                  type="button"
                  phx-click="cancel-existing-entry"
                  phx-value-ref={file_key}
                  phx-value-id={@upload_key}
                  phx-target="#form-component"
                  @click="() => dispatchChangeEvent($el)"
                >
                  &times;
                </button>
              </div>
            <% end %>
          </article>

          <%= if @uploads_allowed do %>
            <p :for={err <- upload_errors(@field_uploads)} class="text-xs italic text-red-500">
              <%= error_to_string(err) %>
            </p>
          <% end %>
          <Backpex.HTML.Form.error :for={msg <- @form_errors}><%= msg %></Backpex.HTML.Form.error>
        </section>
      </Layout.field_container>
    </div>
    """
  end

  @impl Backpex.Field
  def assign_uploads({_name, field_options} = field, socket) do
    field_files = {field_options.upload_key, existing_file_paths(field, socket.assigns.item, [])}

    max_entries = field_options.max_entries
    max_file_size = Map.get(field_options, :max_file_size, 8_000_000)

    if get_in(socket.assigns, [:uploads, field_options.upload_key]) do
      socket
    else
      socket
      |> assign_uploaded_files(field_files)
      |> allow_field_uploads(field_options, max_entries, max_file_size)
    end
  end

  defp assign_uploaded_files(socket, field_files) do
    uploaded_files = Map.get(socket.assigns, :uploaded_files, [])
    assign(socket, :uploaded_files, [field_files | uploaded_files])
  end

  defp allow_field_uploads(socket, _field_options, 0, _max_file_size), do: socket

  defp allow_field_uploads(socket, field_options, max_entries, max_file_size) do
    allow_upload(socket, field_options.upload_key,
      accept: field_options.accept,
      max_entries: max_entries,
      max_file_size: max_file_size
    )
  end

  @doc """
  Returns a list of existing files mapped to a label.
  """
  def existing_file_paths(field, item, removed_files) do
    files = list_existing_files(field, item, removed_files)

    map_file_paths(field, files)
  end

  @doc """
  Lists existing files based on item and list of removed files.
  """
  def list_existing_files({_field_name, field_options} = _field, item, removed_files) do
    %{list_existing_files: list_existing_files} = field_options

    list_existing_files.(item) -- removed_files
  end

  @doc """
  Maps uploaded files to keyword list with identifier and label.
  """
  def map_file_paths({_field_name, field_options} = _field, files) when is_list(files) do
    files
    |> Enum.map(&{&1, label_from_file(field_options, &1)})
  end

  @doc """
  Calls field option function to get label from filename. Defaults to filename.

    ## Examples
      iex> Backpex.Fields.Upload.label_from_file(%{file_label: fn file -> file <> "xyz" end}, "file")
      "filexyz"
      iex> Backpex.Fields.Upload.label_from_file(%{}, "file")
      "file"
  """
  def label_from_file(%{file_label: file_label} = _field_options, file), do: file_label.(file)
  def label_from_file(_field_options, file), do: file

  defp error_to_string(:too_large), do: Backpex.translate("too large")
  defp error_to_string(:too_many_files), do: Backpex.translate("too many files")
  defp error_to_string(:not_accepted), do: Backpex.translate("unacceptable file type")
end
