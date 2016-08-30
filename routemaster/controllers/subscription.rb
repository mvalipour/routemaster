require 'routemaster/controllers'
require 'routemaster/models/topic'
require 'routemaster/models/subscription'
require 'routemaster/services/update_subscription_topics'
require 'routemaster/controllers/parser'
require 'sinatra/base'

module Routemaster
  module Controllers
    class Subscription < Sinatra::Base
      register Parser

      VALID_KEYS = %w(topics callback uuid max timeout)

      post '/subscription', parse: :json do
        # TODO: log this
        halt 400 if (data.keys - VALID_KEYS).any?
        halt 400 unless data['topics'].kind_of?(Array)

        topics = data['topics'].map do |name|
          Models::Topic.find(name) ||
          Models::Topic.new(name: name, publisher: nil)
        end
        halt 404 unless topics.all?

        begin
          sub = Models::Subscription.new(subscriber: request.env['REMOTE_USER'])
          sub.callback   = data['callback']
          sub.uuid       = data['uuid']
          sub.timeout    = data['timeout'] if data['timeout']
          sub.max_events = data['max']     if data['max']
        rescue ArgumentError => e
          # TODO: log this.
          halt 400
        end

        Services::UpdateSubscriptionTopics.new(
          topics:       topics,
          subscription: sub,
        ).call

        halt 204
      end

      delete '/subscriber' do
        _load_subscription.destroy
        halt 204
      end

      delete '/subscriber/topics/:name' do
        sub = _load_subscription
        topic = Models::Topic.find(params['name'])
        if topic.nil?
          halt 404, 'topic not found'
        end
        unless topic.subscribers.include?(sub)
          halt 404, 'not subscribed'
        end
        topic.subscribers.remove(sub)
        halt 204
      end

      # GET /subscriptions
      # [
      #   {
      #     subscriber: <username>,
      #     callback:   <url>,
      #     topics:     [<name>, ...],
      #     events: {
      #       sent:       <sent_count>,
      #       queued:     <queue_size>,
      #       oldest:     <staleness>,
      #     }
      #   }, ...
      # ]

      get '/subscriptions' do
        content_type :json
        payload = Models::Subscription.map do |subscription|
          {
            subscriber: subscription.subscriber,
            callback: subscription.callback,
            topics: subscription.topics.map(&:name),
            events: {
              sent: subscription.all_topics_count,
              queued: subscription.queue.length,
              oldest: subscription.queue.staleness,
            }
          }
        end
        payload.to_json
      end

      private

      def _load_subscription
        sub = Models::Subscription.find(request.env['REMOTE_USER'])
        sub or halt 404, 'subscriber not found'
      end
    end
  end
end