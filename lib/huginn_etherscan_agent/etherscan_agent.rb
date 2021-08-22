module Agents
  class EtherscanAgent < Agent
    include FormConfigurable
    can_dry_run!
    no_bulk_receive!
    default_schedule '1h'

    description do
      <<-MD
      The Github notification agent fetches notifications and creates an event by notification.

      `mark_as_read` is used to post request for mark as read notification.

      `result_limit` is used when you want to limit result per page.

      `real_value` is used for calculating token value with the tokenDecimal applied.

      `with_confirmations` is used to avoid an event as soon as it increases.

      `debug` is used to verbose mode.

      `type` can be tokentx type (you can see api documentation).
      Get a list of "ERC20 - Token Transfer Events" by Address

      `expected_receive_period_in_days` is used to determine if the Agent is working. Set it to the maximum number of days
      that you anticipate passing without this Agent receiving an incoming Event.
      MD
    end

    event_description <<-MD
      Events look like this:

          {
            "blockNumber": "XXXXXXXXX",
            "timeStamp": "XXXXXXXXXX",
            "hash": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
            "nonce": "XXXXXX",
            "blockHash": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
            "from": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
            "contractAddress": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
            "to": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
            "value": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
            "tokenName": "XXX",
            "tokenSymbol": "XXX",
            "tokenDecimal": "xx",
            "transactionIndex": "xx",
            "gas": "XXXXXX",
            "gasPrice": "XXXXXX",
            "gasUsed": "XXXXX",
            "cumulativeGasUsed": "XXXXXX",
            "input": "deprecated",
            "confirmations": "XXXXXX"
          }
    MD

    def default_options
      {
        'wallet_address' => '',
        'changes_only' => 'true',
        'with_confirmations' => 'false',
        'debug' => 'false',
        'real_value' => 'true',
        'expected_receive_period_in_days' => '2',
        'result_limit' => '10',
        'token' => '',
        'type' => 'tokentx'
      }
    end

    form_configurable :wallet_address, type: :string
    form_configurable :changes_only, type: :boolean
    form_configurable :real_value, type: :boolean
    form_configurable :with_confirmations, type: :boolean
    form_configurable :debug, type: :boolean
    form_configurable :token, type: :string
    form_configurable :expected_receive_period_in_days, type: :string
    form_configurable :result_limit, type: :string
    form_configurable :type, type: :array, values: ['account']

    def validate_options
      unless options['wallet_address'].present?
        errors.add(:base, "wallet_address is a required field")
      end

      if options.has_key?('changes_only') && boolify(options['changes_only']).nil?
        errors.add(:base, "if provided, changes_only must be true or false")
      end

      if options.has_key?('with_confirmations') && boolify(options['with_confirmations']).nil?
        errors.add(:base, "if provided, with_confirmations must be true or false")
      end

      if options.has_key?('debug') && boolify(options['debug']).nil?
        errors.add(:base, "if provided, debug must be true or false")
      end

      if options.has_key?('real_value') && boolify(options['real_value']).nil?
        errors.add(:base, "if provided, real_value must be true or false")
      end

      unless options['token'].present?
        errors.add(:base, "token is a required field")
      end

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end

      unless options['result_limit'].present? && options['result_limit'].to_i > 0
        errors.add(:base, "Please provide 'result_limit' to indicate the number of results wanted")
      end
    end

    def working?
      event_created_within?(options['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def check
      fetch
    end

    private

    def real_value(value, decimal)
      value / 10.0**decimal
    end

    def fetch
      uri = URI.parse("http://api.etherscan.io/api")
      request = Net::HTTP::Get.new(uri)
      request.set_form_data(
        "module" => "account",
        "action" => "tokentx",
        "address" => interpolated['wallet_address'],
        "startblock" => "0",
        "endblock" => "999999999",
        "page" => "1",
        "offset" => interpolated['result_limit'],
        "sort" => "desc",
        "apikey" => interpolated['token'],
      )
      
      req_options = {
        use_ssl: uri.scheme == "https",
      }
  
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end
      
      log "request  status : #{response.code}"

      payload = JSON.parse(response.body)

      if interpolated['debug'] == 'true'
        log payload
      end

      if interpolated['with_confirmations'] == 'false'
        payload['result'].each do |tx|
          tx.delete('confirmations')
        end
      end

      if interpolated['real_value'] == 'true'
        payload['result'].each do |tx|
          tx['real_value'] = real_value(tx['value'].to_i, tx['tokenDecimal'].to_i)
        end
      end

      if interpolated['changes_only'] == 'true'
        if payload.to_s != memory['last_status']
          if "#{memory['last_status']}" == ''
            payload['result'].each do |tx|
              create_event payload: tx
            end
          else
            last_status = memory['last_status'].gsub("=>", ": ").gsub(": nil,", ": null,")
            last_status = JSON.parse(last_status)
            payload['result'].each do |tx|
              found = false
              if interpolated['debug'] == 'true'
                log "tx"
                log tx
              end
              last_status['result'].each do |txbis|
                if tx == txbis
                  found = true
                end
                if interpolated['debug'] == 'true'
                  log "txbis"
                  log txbis
                  log "found is #{found}!"
                end
              end
              if found == false
                if interpolated['debug'] == 'true'
                  log "found is #{found}! so event created"
                  log tx
                end
                create_event payload: tx
              end
            end
          end
          memory['last_status'] = payload.to_s
        end
      else
        create_event payload: payload
        if payload.to_s != memory['last_status']
          memory['last_status'] = payload.to_s
        end
      end
    end
  end
end
