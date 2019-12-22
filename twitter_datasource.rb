# frozen_string_literal: true

Plugin.create :twitter_datasource do
  # このプラグインが提供するデータソースを返す
  # ==== Return
  # Hash データソース
  def datasources
    ds = {nested_quoted_myself: _("ナウい引用(全てのアカウント)")}
    Enumerator.new{|yielder|
      Plugin.filtering(:worlds, yielder)
    }.lazy.select{|world|
      world.class.slug == :twitter
    }.each do |twitter|
      ds["nested_quote_quotedby_#{twitter.user_obj.id}".to_sym] = "@#{twitter.user_obj.idname}/" + _('ナウい引用')
    end
    ds
  end

  def active_datasources
    Plugin.filtering(:active_datasources, Set.new).first
  end

  filter_extract_datasources do |ds|
    [ds.merge(datasources)]
  end

  # 管理しているデータソースに値を注入する
  on_appear do |ms|
    ms.each do |message|
      quoted_screen_names = Set.new(
        message.entity.select{ |entity| :urls == entity[:slug] }.map{ |entity|
          matched = Plugin::Twitter::Message::PermalinkMatcher.match(entity[:expanded_url])
          matched[:screen_name] if matched && matched.names.include?("screen_name") })
      quoted_services = Enumerator.new{|y|
        Plugin.filtering(:worlds, y)
      }.select{|world|
        world.class.slug == :twitter
      }.select{|service|
        quoted_screen_names.include? service.user_obj.idname
      }
      unless quoted_services.empty?
        quoted_services.each do |service|
          Plugin.call :extract_receive_message, "nested_quote_quotedby_#{service.user_obj.id}".to_sym, [message]
        end
        Plugin.call :extract_receive_message, :nested_quoted_myself, [message]
      end
    end
  end

  on_appear do |messages|
    Plugin.call :extract_receive_message, :appear, messages
  end

  on_update do |service, messages|
    Plugin.call :extract_receive_message, :update, messages
    if service and service.class.slug == :twitter
      service_datasource = "home_timeline-#{service.user_obj.id}".to_sym
      if active_datasources.include? service_datasource
        Plugin.call :extract_receive_message, service_datasource, messages
      end
    end
  end

  on_mention do |service, messages|
    Plugin.call :extract_receive_message, :mention, messages
    if service.class.slug == :twitter
      service_datasource = "mentions-#{service.user_obj.id}".to_sym
      if active_datasources.include? service_datasource
        Plugin.call :extract_receive_message, service_datasource, messages
      end
    end
  end

  filter_extract_datasources do |datasources|
    datasources = {
      appear: _("受信したすべての投稿"),
      update: _("ホームタイムライン(全てのアカウント)"),
      mention: _("自分宛ての投稿(全てのアカウント)")
    }.merge datasources
    Enumerator.new{|y|
      Plugin.filtering(:worlds, y)
    }.lazy.select{|world|
      world.class.slug == :twitter
    }.map(&:user_obj).each{ |user|
      datasources.merge!(
        { "home_timeline-#{user.id}".to_sym => "@#{user.idname}/" + _("Home Timeline"),
          "mentions-#{user.id}".to_sym => "@#{user.idname}/" + _("Mentions")
        }
      )
    }
    [datasources] end

end
