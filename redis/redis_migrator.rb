# Original Author: Matt Casper (@mcasper/mattc@procore.com)

require 'redis'

# These can be new Redis servers, these can be different namespaces on the same
# Redis server, whatever. Replace these with the appropriate Redis connections.
# All keys from `old_redis` will be moved with the appropriate values to
# `new_redis`.
old_redis = Redis.new
new_redis = Redis.new

old_redis.keys.each do |key|
  begin
    case old_redis.type(key)
    when "string"
      new_redis.set(key, old_redis.get(key))
    when "list"
      # This should preserve the list's ordering as well (if it was sorted),
      # because we walk the list by index and then push to the end of the list.
      (0..old_redis.llen(key)).each do |i|
        value = old_redis.lindex(key, i)
        new_redis.lpush(key, value)
      end
    when "set"
      members = old_redis.smembers(key)
      members.each do |member|
        new_redis.sadd(key, member)
      end
    when "zset"
      # This ranges over all the keys in the zset, making sure to get back
      # the scores as well. They scores/values are returned in reverse order
      # than what you set them in, which is why we have to map reverse
      # over all the sets we get back.
      zsets = old_redis.zrange(key, 0, -1, with_scores: true)
      new_redis.zadd(key, zsets.map(&:reverse))
    when "hash"
      hash = old_redis.hgetall(key)
      hash.each do |hkey, hvalue|
        new_redis.hset(key, hkey, hvalue)
      end
    end
  rescue Redis::CommandError => e
    puts "Sadness! Failed on key #{key} with type #{old_redis.type(key)} with error #{e}."
  end
end

puts "Successfully migrated keys from #{old_redis.inspect} to #{new_redis.inspect}"
