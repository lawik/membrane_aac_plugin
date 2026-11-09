defmodule Membrane.AAC.Parser.Esds do
  @moduledoc """
  Utility functions for parsing and generating `esds` atom.

  It's structure is defined in ISO/IEC 14496-1.
  """

  alias Membrane.AAC
  alias Membrane.AAC.Parser.AudioSpecificConfig

  @spec generate_esds(AAC.t(), Membrane.Element.state()) :: binary()
  def generate_esds(stream_format, state) do
    section5 =
      generate_esds_section(AudioSpecificConfig.generate_audio_specific_config(stream_format), 5)

    # 64 = mpeg4-audio
    object_type_id = 64
    # 5 = audio
    stream_type = 5
    upstream_flag = 0
    reserved_flag_set_to_1 = 1
    buffer_size = 0

    section4 =
      <<object_type_id, stream_type::6, upstream_flag::1, reserved_flag_set_to_1::1,
        buffer_size::24, state.max_bit_rate::32, state.avg_bit_rate::32, section5::binary>>
      |> generate_esds_section(4)

    section6 = <<2>> |> generate_esds_section(6)

    elementary_stream_id = 1
    stream_priority = 0

    <<elementary_stream_id::16, stream_priority, section4::binary, section6::binary>>
    |> generate_esds_section(3)
  end

  defp generate_esds_section(payload, section_no) do
    type_tag = <<128, 128, 128>>
    <<section_no, type_tag::binary, byte_size(payload), payload::binary>>
  end

  @doc """
  Parses the `esds` atom, returning an error if it is malformed or describes a
  stream that is not supported.
  """
  @spec parse_esds(binary()) :: {:ok, AAC.t()} | {:error, reason :: term()}
  def parse_esds(esds) do
    with {:ok, section_3, <<>>} <- unpack_esds_section(esds, 3),
         {:ok, rest} <- parse_es_descriptor_header(section_3),
         {:ok, section_4, esds_section_6} <- unpack_esds_section(rest, 4),
         {:ok, <<2>>, <<>>} <- unpack_esds_section(esds_section_6, 6),
         {:ok, esds_section_5} <- parse_decoder_config_descriptor(section_4),
         {:ok, section_5, <<>>} <- unpack_esds_section(esds_section_5, 5),
         {:ok, stream_format} <- AudioSpecificConfig.parse_audio_specific_config(section_5) do
      {:ok, Map.put(stream_format, :config, {:esds, esds})}
    else
      {:error, _reason} = error -> error
      _unexpected_section -> {:error, :invalid_esds}
    end
  end

  defp parse_es_descriptor_header(
         <<_elementary_stream_id::16, stream_dependence_flag::1, url_flag::1, ocr_stream_flag::1,
           _stream_priority::5, rest::binary>>
       ) do
    with {:ok, rest} <- skip(rest, if(stream_dependence_flag != 0, do: 2, else: 0)),
         {:ok, rest} <- skip_url(rest, url_flag),
         {:ok, rest} <- skip(rest, if(ocr_stream_flag != 0, do: 2, else: 0)) do
      {:ok, rest}
    end
  end

  defp parse_es_descriptor_header(_too_short), do: {:error, :invalid_esds}

  defp skip(binary, size) do
    case binary do
      <<_skipped::binary-size(^size), rest::binary>> -> {:ok, rest}
      _too_short -> {:error, :invalid_esds}
    end
  end

  defp skip_url(binary, 0), do: {:ok, binary}
  defp skip_url(<<url_length::8, rest::binary>>, _url_flag), do: skip(rest, url_length)
  defp skip_url(_too_short, _url_flag), do: {:error, :invalid_esds}

  defp parse_decoder_config_descriptor(section_4) do
    # 64 = mpeg4-audio
    object_type_id = 64
    # 5 = audio
    stream_type = 5
    upstream_flag = 0

    # The trailing bit of this byte is "reserved" and ISO/IEC 14496-1 mandates
    # it be set to 1. Some encoders leave it cleared (emitting 0x14 instead of
    # 0x15), so we accept either value rather than crashing on otherwise-valid
    # streams.
    case section_4 do
      <<^object_type_id, ^stream_type::6, ^upstream_flag::1, _reserved_flag::1, _buffer_size::24,
        _max_bit_rate::32, _avg_bit_rate::32, esds_section_5::binary>> ->
        {:ok, esds_section_5}

      _unexpected_descriptor ->
        {:error, :invalid_esds}
    end
  end

  defp unpack_esds_section(section, section_no) do
    type_tag = <<128, 128, 128>>

    case section do
      <<^section_no::8-integer, ^type_tag::binary-size(3), payload_size::8-integer,
        payload::binary-size(payload_size), rest::binary>> ->
        {:ok, payload, rest}

      <<^section_no::8-integer, payload_size::8-integer, payload::binary-size(payload_size),
        rest::binary>> ->
        {:ok, payload, rest}

      _unexpected_section ->
        {:error, :invalid_esds}
    end
  end
end
