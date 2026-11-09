defmodule Membrane.AAC.Parser.AudioSpecificConfig do
  @moduledoc """
  Utility functions for parsing and generating Audio Specific Config.

  It's spec is described in section 1.6.2.1 of ISO/IEC 14496-3.
  """

  alias Membrane.AAC

  @spec generate_audio_specific_config(AAC.t()) :: binary()
  def generate_audio_specific_config(stream_format) do
    aot = AAC.profile_to_aot_id(stream_format.profile)
    frequency_id = AAC.sample_rate_to_sampling_frequency_id(stream_format.sample_rate)
    channel_config_id = AAC.channels_to_channel_config_id(stream_format.channels)
    frame_length_id = AAC.samples_per_frame_to_frame_length_id(stream_format.samples_per_frame)

    depends_on_core_coder = 0
    extension_flag = 0

    custom_frequency = if frequency_id == 15, do: <<stream_format.sample_rate::24>>, else: <<>>

    <<aot::5, frequency_id::4, custom_frequency::binary, channel_config_id::4, frame_length_id::1,
      depends_on_core_coder::1, extension_flag::1>>
  end

  @doc """
  Parses the Audio Specific Config, returning an error if it is malformed or
  describes a stream that is not supported.
  """
  @spec parse_audio_specific_config(binary()) :: {:ok, AAC.t()} | {:error, reason :: term()}
  def parse_audio_specific_config(audio_specific_config) do
    with {:ok, aot, frequency_id, rest} <- parse_header(audio_specific_config),
         {:ok, sample_rate, rest} <- parse_sample_rate(frequency_id, rest),
         {:ok, channel_config_id, frame_length_id} <- parse_channels_and_frame_length(rest),
         {:ok, profile} <- lookup(&AAC.aot_id_to_profile/1, aot, :audio_object_type),
         {:ok, channels} <-
           lookup(&AAC.channel_config_id_to_channels/1, channel_config_id, :channel_config) do
      {:ok,
       %AAC{
         profile: profile,
         mpeg_version: 4,
         sample_rate: sample_rate,
         channels:
           case channels do
             :AOT_specific -> nil
             channels -> channels
           end,
         encapsulation: :none,
         samples_per_frame: AAC.frame_length_id_to_samples_per_frame(frame_length_id),
         config: {:audio_specific_config, audio_specific_config}
       }}
    end
  end

  defp parse_header(<<aot::5, frequency_id::4, rest::bitstring>>),
    do: {:ok, aot, frequency_id, rest}

  defp parse_header(_too_short), do: {:error, :invalid_audio_specific_config}

  defp parse_sample_rate(15, <<custom_frequency::24, rest::bitstring>>),
    do: {:ok, custom_frequency, rest}

  defp parse_sample_rate(15, _too_short), do: {:error, :invalid_audio_specific_config}

  defp parse_sample_rate(frequency_id, rest) do
    with {:ok, sample_rate} <-
           lookup(&AAC.sampling_frequency_id_to_sample_rate/1, frequency_id, :sampling_frequency) do
      {:ok, sample_rate, rest}
    end
  end

  defp parse_channels_and_frame_length(<<channel_config_id::4, frame_length_id::1, _rest::bits>>),
    do: {:ok, channel_config_id, frame_length_id}

  defp parse_channels_and_frame_length(_too_short), do: {:error, :invalid_audio_specific_config}

  # The `Membrane.AAC` lookups raise on ids that are reserved or not supported
  defp lookup(fun, id, name) do
    {:ok, fun.(id)}
  rescue
    ArgumentError -> {:error, {:unsupported, name, id}}
  end
end
