module Lita
  module Handlers
    class Standup < Handler
      # General settings
      config :time_to_respond, types: [Integer, Float], default: 60 #minutes
      config :summary_email_recipients, type: Array, default: ['you@company.com'], required: true
      config :name_of_auth_group, type: Symbol, default: :standup_participants, required: true
      config :questions, type: Array, required: false, default: ['1', '2', '3']

      ## SMTP Mailer Settings ##
      config :address, type: String, required: true
      config :port, type: Integer, required: true
      config :domain, type: String, required: true
      config :user_name, type: String, required: true
      config :password, type: String, required: true
      config :authentication, type: String, required: true
      config :enable_starttls_auto, types: [TrueClass, FalseClass], required: true
      config :robot_email_address, type: String, default: 'noreply@lita.com', required: true
      config :email_subject_line, type: String, default: "Standup summary for --today--", required: true  #interpolated at runtime

      on :loaded, :setup

      def setup(payload)
        config.questions.each_with_index do |q, i|
          redis.set("question-#{i}", q)
        end
      end


      route %r{^start standup now}i, :begin_standup, command: true, restrict_to: :standup_admins
      route /standup response (.*)/i, :process_standup, command: false

      def begin_standup(request)
        redis.set('last_standup_started_at', Time.now)
        find_and_create_users
        message_all_users
        SummaryEmailJob.new().async.later(config.time_to_respond * 60, {redis: redis, config: config})
      end

      def process_standup(request)
        return unless timing_is_right?
        result = /(#{config.questions.first}.*)(?:\s|\n)(#{config.questions[1]}.*)(?:\s|\n)(#{config.questions[2]}.*)/.request.matches.first
        result = request.matches.first if result.nil?
        request.reply('Response recorded. Thanks for partipating')
        date_string = Time.now.strftime('%Y%m%d')
        user_name = request.user.name.split(' ').join('_') #lol
        redis.set(date_string + '-' + user_name, result.matches.first)
      end

      private

      def message_all_users
        @users.each do |user|
          source = Lita::Source.new(user: user)
          robot.send_message(source, "Time for standup!")
          robot.send_message(source, "Please tell me what you did yesterday,
                                    what you're doing now, and what obsticles
                                    are impeading your progress. Please prepend your
                                    answer with 'standup response'")
        end
      end

      def find_and_create_users
        @users ||= robot.auth.groups_with_users[config.name_of_auth_group]
      end

      def timing_is_right?
        return false if redis.get('last_standup_started_at').nil?
        intitiated_at = Time.parse(redis.get('last_standup_started_at'))
        Time.now > intitiated_at && intitiated_at + (60*config.time_to_respond) > Time.now
      end

    end
    Lita.register_handler(Standup)
  end
end



