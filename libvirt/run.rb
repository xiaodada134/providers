#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require 'digest/md5'
require_relative "#{ENV['CCI_SRC']}/lib/log"
require_relative "#{ENV['CCI_SRC']}/lib/sched_client"
require_relative "#{ENV['CCI_SRC']}/providers/lib/context"
require_relative "#{ENV['CCI_SRC']}/providers/lib/resource"
require_relative "#{ENV['CCI_SRC']}/providers/lib/domain"
require_relative "#{ENV['CCI_SRC']}/providers/lib/libvirt"

def create_logger(hostname)
  filename = "#{hostname}.log"
  File.delete(filename) if FileTest.exist?(filename)
  Log.new filename
end

def compute_mac(string)
  /(..)(..)(..)(..)(..)/ =~ Digest::MD5.hexdigest(string)
  "0a:#{$1}:#{$2}:#{$3}:#{$4}:#{$5}"
end

def job_exist?(response)
  flag = false
  if response['job_id'].empty?
    puts '----------'
    puts 'No job now'
    puts '----------'
    flag = true
  end
  return flag
end

def request_job(context, sched_client, logger)
  mac = context.info['mac']
  hostname = context.info['hostname']
  queues = context.info['queues']
  sched_client.register_mac2host(hostname, mac)
  sched_client.register_host2queues(hostname, queues)
  response = JSON.parse(sched_client.consume_job('libvirt', 'mac', mac))
  if job_exist?(response)
    logger.info('No job now')
    sched_client.delete_mac2host(mac)
    sched_client.delete_host2queues(hostname)
    response = nil
  end
  return response
end

def parse_response(response, context, resource)
  context.merge!(response)
  resource.parse_response(response)
  context.merge!(resource.info)
end

def generate_domain(domain, logger)
  xml_path = ''
  begin
    domain.generate
    xml_path = domain.save_to('domain.xml')
  rescue StandardError => e
    logger.error(e)
    logger.error('please check your xml file format')
  ensure
    # upload logger
    puts 'upload logger'
  end
  return xml_path
end

def start(context, logger, libvirt)
  domain = Domain.new(context, logger)
  xml_path = generate_domain(domain, logger)
  return if xml_path.empty?

  begin
    libvirt.define(xml_path)
    libvirt.create
    libvirt.wait
  rescue StandardError => e
    logger.error(e)
  ensure
    # upload logger
    puts 'upload logger'
  end
end

def clean(context, sched_client, libvirt)
  sched_client.delete_mac2host(context.info['mac'])
  sched_client.delete_host2queues(context.info['hostname'])
  libvirt.close
end

def main(hostname, queues)
  logger = create_logger(hostname)
  mac = compute_mac hostname
  context = Context.new(mac, hostname, queues)
  libvirt = LibvirtConnect.new
  resource = Resource.new(hostname, logger)
  sched_client = SchedClient.new
  response = request_job(context, sched_client, logger)
  return if response.nil?

  parse_response(response, context, resource)
  start(context, logger, libvirt)
  clean(context, sched_client, libvirt)
end
