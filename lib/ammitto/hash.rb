class Hash
  def symbolize_keys!
    self.keys.each do |k|
      if self[k].is_a? Hash
        self[k].symbolize_keys!
      end
      if k.is_a? String
        raise RuntimeError, "Symbolizing key '#{k}' means overwrite some data (key :#{k} exists)" if self[k.to_sym]
        self[k.to_sym] = self[k]
        self.delete(k)
      end
    end
    return self
  end
end
