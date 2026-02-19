require "json"
require "./types"
require "./openai_compat"
require "./anthropic"
require "../config/config"

module CrystalClaw
  module Providers
    # Factory — creates appropriate provider from config
    def self.create_provider(cfg : Config) : LLMProvider
      model = cfg.agents.defaults.model

      # Determine provider from model string or config
      provider_name = detect_provider(model, cfg)

      case provider_name
      when "anthropic"
        api_key = cfg.providers.anthropic.api_key
        raise "Anthropic API key not configured" if api_key.empty?
        api_base = cfg.providers.anthropic.api_base
        api_base = "https://api.anthropic.com" if api_base.empty?
        # Strip provider prefix from model
        clean_model = model.sub(/^anthropic\//, "")
        AnthropicProvider.new(api_key, api_base, clean_model, cfg.providers.anthropic.read_timeout)
      when "openrouter"
        api_key = cfg.providers.openrouter.api_key
        raise "OpenRouter API key not configured" if api_key.empty?
        api_base = cfg.providers.openrouter.api_base
        api_base = "https://openrouter.ai/api/v1" if api_base.empty?
        OpenAICompatProvider.new(api_key, api_base, model, cfg.providers.openrouter.read_timeout)
      when "ollama"
        api_key = cfg.providers.ollama.api_key
        raise "Ollama API key not configured" if api_key.empty?
        api_base = cfg.providers.ollama.api_base
        api_base = "http://localhost:11434/v1" if api_base.empty?
        OpenAICompatProvider.new(api_key, api_base, model, cfg.providers.ollama.read_timeout)
      when "openai"
        api_key = cfg.providers.openai.api_key
        raise "OpenAI API key not configured" if api_key.empty?
        api_base = cfg.providers.openai.api_base
        api_base = "https://api.openai.com/v1" if api_base.empty?
        clean_model = model.sub(/^openai\//, "")
        OpenAICompatProvider.new(api_key, api_base, clean_model, cfg.providers.openai.read_timeout)
      when "gemini"
        api_key = cfg.providers.gemini.api_key
        raise "Gemini API key not configured" if api_key.empty?
        api_base = cfg.providers.gemini.api_base
        api_base = "https://generativelanguage.googleapis.com/v1beta/openai" if api_base.empty?
        clean_model = model.sub(/^gemini\//, "")
        OpenAICompatProvider.new(api_key, api_base, clean_model, cfg.providers.gemini.read_timeout)
      when "zhipu"
        api_key = cfg.providers.zhipu.api_key
        raise "Zhipu API key not configured" if api_key.empty?
        api_base = cfg.providers.zhipu.api_base
        api_base = "https://open.bigmodel.cn/api/paas/v4" if api_base.empty?
        clean_model = model.sub(/^zhipu\//, "")
        OpenAICompatProvider.new(api_key, api_base, clean_model, cfg.providers.zhipu.read_timeout)
      when "groq"
        api_key = cfg.providers.groq.api_key
        raise "Groq API key not configured" if api_key.empty?
        api_base = cfg.providers.groq.api_base
        api_base = "https://api.groq.com/openai/v1" if api_base.empty?
        clean_model = model.sub(/^groq\//, "")
        OpenAICompatProvider.new(api_key, api_base, clean_model, cfg.providers.groq.read_timeout)
      when "deepseek"
        api_key = cfg.providers.deepseek.api_key
        raise "DeepSeek API key not configured" if api_key.empty?
        api_base = cfg.providers.deepseek.api_base
        api_base = "https://api.deepseek.com/v1" if api_base.empty?
        clean_model = model.sub(/^deepseek\//, "")
        OpenAICompatProvider.new(api_key, api_base, clean_model, cfg.providers.deepseek.read_timeout)
      when "vllm"
        api_base = cfg.providers.vllm.api_base
        raise "vLLM API base not configured" if api_base.empty?
        api_key = cfg.providers.vllm.api_key
        api_key = "not-needed" if api_key.empty?
        OpenAICompatProvider.new(api_key, api_base, model, cfg.providers.vllm.read_timeout)
      else
        # Default: try to find any configured provider
        create_fallback_provider(cfg, model)
      end
    end

    private def self.detect_provider(model : String, cfg : Config) : String
      # Check explicit provider setting
      provider = cfg.agents.defaults.provider
      return provider unless provider.empty?

      # Detect from model name prefix
      if model.starts_with?("anthropic/") || model.starts_with?("claude")
        return "anthropic"
      elsif model.starts_with?("openrouter/") || model.includes?("/")
        return "openrouter"
      elsif model.starts_with?("gpt-") || model.starts_with?("o1") || model.starts_with?("o3")
        return "openai"
      elsif model.starts_with?("gemini")
        return "gemini"
      elsif model.starts_with?("glm-")
        return "zhipu"
      elsif model.starts_with?("deepseek")
        return "deepseek"
      elsif model.starts_with?("llama") || model.starts_with?("mixtral")
        return "groq"
      end

      # Check which providers have API keys set
      return "openrouter" unless cfg.providers.openrouter.api_key.empty?
      return "anthropic" unless cfg.providers.anthropic.api_key.empty?
      return "openai" unless cfg.providers.openai.api_key.empty?
      return "gemini" unless cfg.providers.gemini.api_key.empty?
      return "zhipu" unless cfg.providers.zhipu.api_key.empty?
      return "groq" unless cfg.providers.groq.api_key.empty?
      return "deepseek" unless cfg.providers.deepseek.api_key.empty?
      return "vllm" unless cfg.providers.vllm.api_base.empty?

      "openrouter" # fallback default
    end

    private def self.create_fallback_provider(cfg : Config, model : String) : LLMProvider
      # Try providers in priority order
      unless cfg.providers.openrouter.api_key.empty?
        base = cfg.providers.openrouter.api_base
        base = "https://openrouter.ai/api/v1" if base.empty?
        return OpenAICompatProvider.new(cfg.providers.openrouter.api_key, base, model, cfg.providers.openrouter.read_timeout)
      end

      unless cfg.providers.openai.api_key.empty?
        base = cfg.providers.openai.api_base
        base = "https://api.openai.com/v1" if base.empty?
        return OpenAICompatProvider.new(cfg.providers.openai.api_key, base, model, cfg.providers.openai.read_timeout)
      end

      unless cfg.providers.anthropic.api_key.empty?
        base = cfg.providers.anthropic.api_base
        base = "https://api.anthropic.com" if base.empty?
        return AnthropicProvider.new(cfg.providers.anthropic.api_key, base, model, cfg.providers.anthropic.read_timeout)
      end

      raise "No LLM provider configured. Add an API key to ~/.crystalclaw/config.json"
    end

    # Fallback chain — tries multiple providers/models
    class FallbackChain
      @cooldowns : Hash(String, Time)
      @cooldown_duration : Time::Span

      def initialize(@cooldown_duration = 60.seconds)
        @cooldowns = {} of String => Time
      end

      def chat_with_fallback(
        primary : LLMProvider,
        fallback_providers : Array(LLMProvider),
        messages : Array(Message),
        tools : Array(ToolDefinition),
        model : String,
        fallback_models : Array(String),
        options : Hash(String, JSON::Any)? = nil,
      ) : LLMResponse
        # Try primary
        unless cooled_down?(model)
          begin
            return primary.chat(messages, tools, model, options)
          rescue ex : FailoverError
            if ex.retriable?
              mark_cooldown(model)
              Logger.warn("provider", "Primary failed, trying fallback: #{ex.message}")
            else
              raise ex
            end
          end
        end

        # Try fallbacks
        fallback_models.each_with_index do |fb_model, i|
          next if cooled_down?(fb_model)
          provider = fallback_providers[i]? || primary
          begin
            return provider.chat(messages, tools, fb_model, options)
          rescue ex : FailoverError
            if ex.retriable?
              mark_cooldown(fb_model)
              Logger.warn("provider", "Fallback #{fb_model} failed: #{ex.message}")
            else
              raise ex
            end
          end
        end

        raise FailoverError.new(FailoverReason::Unknown, "all", model, 0,
          Exception.new("All providers failed"))
      end

      private def cooled_down?(model : String) : Bool
        if cooldown_time = @cooldowns[model]?
          Time.utc < cooldown_time
        else
          false
        end
      end

      private def mark_cooldown(model : String)
        @cooldowns[model] = Time.utc + @cooldown_duration
      end
    end
  end
end
