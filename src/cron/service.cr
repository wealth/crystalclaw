require "json"
require "../logger/logger"

module CrystalClaw
  module Cron
    struct CronSchedule
      include JSON::Serializable

      property kind : String # "every", "cron", "once"
      property every_ms : Int64?
      property expr : String?

      def initialize(@kind = "once", @every_ms = nil, @expr = nil)
      end
    end

    struct CronJobState
      include JSON::Serializable

      property next_run_at_ms : Int64?
      property last_run_at_ms : Int64?
      property run_count : Int32

      def initialize(@next_run_at_ms = nil, @last_run_at_ms = nil, @run_count = 0)
      end
    end

    class CronJob
      include JSON::Serializable

      property id : String
      property name : String
      property schedule : CronSchedule
      property message : String
      property enabled : Bool
      property deliver : Bool
      property channel : String
      property to : String
      property state : CronJobState

      def initialize(
        @id = "",
        @name = "",
        @schedule = CronSchedule.new,
        @message = "",
        @enabled = true,
        @deliver = false,
        @channel = "",
        @to = "",
        @state = CronJobState.new,
      )
      end
    end

    class Service
      CRON_KEY = "_cron/jobs"
      @store : Memory::Store
      @jobs : Array(CronJob)
      @running : Bool
      @on_job : Proc(CronJob, String)?

      def initialize(@store, @on_job = nil)
        @jobs = load_jobs
        @running = false
      end

      def set_on_job(&block : CronJob -> String)
        @on_job = block
      end

      def start
        @running = true
        spawn do
          scheduler_loop
        end
      end

      def stop
        @running = false
      end

      def add_job(name : String, schedule : CronSchedule, message : String,
                  deliver : Bool = false, channel : String = "", to : String = "") : CronJob
        job = CronJob.new(
          id: generate_id,
          name: name,
          schedule: schedule,
          message: message,
          deliver: deliver,
          channel: channel,
          to: to,
        )

        # Set next run time
        now_ms = Time.utc.to_unix_ms
        case schedule.kind
        when "every"
          job.state.next_run_at_ms = now_ms + (schedule.every_ms || 60000_i64)
        when "once"
          job.state.next_run_at_ms = now_ms + (schedule.every_ms || 60000_i64)
        end

        @jobs << job
        save_job(job)
        job
      end

      def remove_job(job_id : String) : Bool
        initial_size = @jobs.size
        @jobs.reject! { |j| j.id == job_id }
        if @jobs.size < initial_size
          @store.delete_cron_job(job_id)
          true
        else
          false
        end
      end

      def enable_job(job_id : String, enabled : Bool) : CronJob?
        job = @jobs.find { |j| j.id == job_id }
        if job
          job.enabled = enabled
          save_job(job)
        end
        job
      end

      def list_jobs(include_disabled : Bool = false) : Array(CronJob)
        if include_disabled
          @jobs
        else
          @jobs.select(&.enabled)
        end
      end

      private def scheduler_loop
        while @running
          sleep 10.seconds
          next unless @running

          now_ms = Time.utc.to_unix_ms
          @jobs.each do |job|
            next unless job.enabled
            next_run = job.state.next_run_at_ms
            next unless next_run
            next if now_ms < next_run

            begin
              Logger.info("cron", "Executing job: #{job.name}")
              handler = @on_job
              if handler
                handler.call(job)
              end

              job.state.last_run_at_ms = now_ms
              job.state.run_count += 1

              # Schedule next run
              case job.schedule.kind
              when "every"
                job.state.next_run_at_ms = now_ms + (job.schedule.every_ms || 60000_i64)
              when "once"
                job.enabled = false
              end

              save_job(job)
            rescue ex
              Logger.error("cron", "Job #{job.name} error: #{ex.message}")
            end
          end
        end
      end

      private def load_jobs : Array(CronJob)
        jobs = [] of CronJob
        @store.list_cron_jobs.each do |tuple|
          id, content = tuple
          begin
            jobs << CronJob.from_json(content)
          rescue
            # Skip invalid jobs
          end
        end
        jobs
      end

      private def save_job(job : CronJob)
        @store.set_cron_job(job.id, job.to_json)
      end

      private def generate_id : String
        "job_#{Time.utc.to_unix_ms}_#{Random.rand(1000)}"
      end
    end
  end
end
