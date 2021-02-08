require_relative '../lib/ammitto/processor'

Ammitto::Processor.prepare ||
  raise('Error while getting data ready')