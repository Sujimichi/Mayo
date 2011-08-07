class CukeResultReader
  attr_reader :results, :failed_steps, :failing_scenarios, :summaries

  def initialize results
    @results = results
  end

  def process_results
    collect_failed_steps
  end

  def collect_failed_steps
    @failed_steps = []
    @failing_scenarios = []
    @summaries = []
    
    @results.each do |result|
      steps = []
      scens = []
      summs = []
      add_failed_step_line = false
      add_failed_scen_line = false
      result.each do |line|
        add_failed_step_line = false if line.include?("Failing Scenarios:")
        steps << line if add_failed_step_line unless line.empty?
        add_failed_step_line = true if line.include?("(::) failed steps (::)")

        add_failed_scen_line = false if line.match(/(\d+) scenarios \(/)
        scens << line if add_failed_scen_line unless line.empty?
        add_failed_scen_line = true if line.include?("Failing Scenarios:")

        summs << line if line.match(/(\d+) scenario(s|:?) \(/)
        summs << line if line.match(/(\d+) step(s|:?) \(/)
        summs << line if line.match(/(\d+)m(\d+).(\d+)s/)

      end
      @failed_steps << steps unless steps.empty?
      @failing_scenarios << scens unless steps.empty?
      @summaries << summs
    end

    @failing_scenarios.flatten!
    
  end

  def summary
    n= {}
    #n[:scenarios] = @summaries.map{|s| s[0].match(/(\d+) scenarios/).values_at(1)}.flatten.map{|s| s.to_i}.inject{|i,j| i+j}
    thangs = {:scenarios => 0, :steps => 1}

    types = {:scenarios => "\e[0m", :steps => "\e[0m", :failed => "\e[31m", :skipped => "\e[36m", :passed => "\e[32m"}
    col_reset = "\e[0m"

    thangs.each do |k,v|
    types.each do |type, _|
      collected = @summaries.map{|s| 
        m = s[v].match(/(\d+) #{type}/)
        m = s[v].match(/(\d+) scenario(s|:?)/) if type.eql?(:senarios)
        m.values_at(1) if m
      }.flatten.compact.map{|s| s.to_i}.inject{|i,j| i+j}
      n["#{k}_#{type}".to_sym] = collected unless collected.nil?
    end

    end

    output = []
    thangs.each do |k,v|
      o = []
      o << "#{n["#{k}_#{k}".to_sym]} #{k}"
      t_keys = n.keys.select{|nk| nk.to_s.match(/^#{k}_/)}
      next if t_keys.empty?
      p = t_keys.map{|key|
        skey = key.to_s.sub("#{k}_", "")
        "#{types[skey.to_sym]}#{n[key]} #{skey}#{col_reset}" unless key.to_s.eql?("#{k}_#{k}")
      }.compact.join(", ")
      o << " (#{p})"
      output << o.join
    end

    times = @summaries.map{|s| s[2]}
    times = times.map{|t1|
      m = t1.match(/^(\d+)m/).values_at(1)[0].to_i * 60 * 1000
      s = t1.match(/m(\d+)./).values_at(1)[0].to_i * 1000
      ms = t1.match(/.(\d+)s/).values_at(1)[0].to_i
      [m, s, ms].inject{|i,j| i + j}
    }.inject{|i,j| i + j}

    m = times / 60000
    s = (times - (m*60000)) / 1000
    ms = times - ((m*60000) + (s*1000))
    until ms.to_s.each_char.to_a.size.eql?(3)
      ms = ms.to_s.each_char.to_a.reverse.push(0).reverse.join
    end
    time = "#{m}m#{s}.#{ms}s"

    output << time

    output
  end

end




