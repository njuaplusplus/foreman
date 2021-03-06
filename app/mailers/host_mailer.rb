require 'uri'

class HostMailer < ApplicationMailer
  helper :reports

  # sends out a summary email of hosts and their metrics (e.g. how many changes failures etc).
  def summary(options = {})
    raise ::Foreman::Exception.new(N_("Must specify a valid user with email enabled")) unless (user=User.find(options[:user]))
    hosts = Host::Managed.authorized_as(user, :view_hosts, Host)
    time = options[:time] || 1.day.ago
    host_data = Report.summarise(time, hosts.all).sort

    total_metrics = load_metrics(host_data)
    total = 0; total_metrics.values.each { |v| total += v }

    subject = _("Puppet Summary Report - F:%{failed} R:%{restarted} S:%{skipped} A:%{applied} FR:%{failed_restarts} T:%{total}") % {
      :failed => total_metrics["failed"],
      :restarted => total_metrics["restarted"],
      :skipped => total_metrics["skipped"],
      :applied => total_metrics["applied"],
      :failed_restarts => total_metrics["failed_restarts"],
      :total => total
    }

    @hosts = host_data
    @timerange = time
    @out_of_sync = hosts.out_of_sync
    @disabled = hosts.alerts_disabled

    set_url
    set_locale_for user

    mail(:to   => user.mail,
         :from => Setting["email_reply_address"],
         :subject => subject,
         :date => Time.zone.now )
  end

  def error_state(report)
    report = Report.find(report)
    host = report.host
    owners = host.owner.recipients_for(:puppet_error_state) if host.owner.present?
    owners ||= []
    raise ::Foreman::Exception.new(N_("unable to find recipients")) if owners.empty?
    @report = report
    @host = host

    group_mail(owners, :subject => (_("Puppet error on %s") % host.to_label))
  end

  private

  def set_url
    unless (@url = URI.parse(Setting[:foreman_url])).present?
      raise ":foreman_url is not set, please configure in the Foreman Web UI (More -> Settings -> General)"
    end
  end

  def load_metrics(host_data)
    total_metrics = {"failed"=>0, "restarted"=>0, "skipped"=>0, "applied"=>0, "failed_restarts"=>0}

    host_data.flatten.delete_if { |x| true unless x.is_a?(Hash) }.each do |data_hash|
      total_metrics["failed"]          += data_hash[:metrics]["failed"]
      total_metrics["restarted"]       += data_hash[:metrics]["restarted"]
      total_metrics["skipped"]         += data_hash[:metrics]["skipped"]
      total_metrics["applied"]         += data_hash[:metrics]["applied"]
      total_metrics["failed_restarts"] += data_hash[:metrics]["failed_restarts"]
    end

    total_metrics
  end
end
