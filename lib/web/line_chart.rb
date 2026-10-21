module Web
  # LineChartComponent's geometry: one line over time in a fixed 760 × 252
  # box, the scale's ceiling rounded up to something a person would pick,
  # four gridlines, the last point marked. Same arithmetic in the same
  # order as the component, so every coordinate is the same double; `num`
  # prints it the way JavaScript does (no ".0" on a whole number).
  class LineChart
    W = 760
    H = 252
    LEFT = 48
    RIGHT = 744
    TOP = 12
    BOTTOM = 212
    BASELINE = 236

    Point = Struct.new(:label, :value, :x, :y, keyword_init: true)

    attr_reader :points

    # points: [[label, value]]; tick: formats a gridline's value.
    def initialize(points, tick: ->(n) { Web::LineChart.num(n) })
      @source = points.map { |label, value| [ label, value.to_f ] }
      @tick = tick
      @points = plot
    end

    def self.num(value)
      value == value.to_i ? value.to_i.to_s : value.to_s
    end

    def ceiling
      max = [ 0.0, *@source.map(&:last) ].max
      return 4 if max <= 0

      magnitude = 10.0**Math.log10(max).floor
      (max / magnitude * 1.05).ceil * magnitude
    end

    def grid_lines
      c = ceiling.to_f
      (0..3).map do |i|
        { y: BOTTOM - ((BOTTOM - TOP) / 3.0) * i, label: @tick.call((c / 3) * i), strong: i.zero? }
      end
    end

    def last
      @points.last
    end

    def line_path
      "M #{@points.map { |p| "#{self.class.num(p.x)} #{self.class.num(p.y)}" }.join(' L ')}"
    end

    def area_path
      return "" if @points.empty?

      "#{line_path} L #{RIGHT} #{BOTTOM} L #{LEFT} #{BOTTOM} Z"
    end

    # The marker sits left of the last point so it cannot run off the edge.
    def marker_x
      [ (last&.x || 0) - 118, RIGHT - 118 ].min
    end

    def marker_y
      [ TOP - 6, (last&.y || 0) - 52 ].max
    end

    def end?(index)
      index.zero? || index == @points.size - 1
    end

    private

    def plot
      return [] if @source.empty?

      c = ceiling.to_f
      step = @source.size > 1 ? (RIGHT - LEFT).to_f / (@source.size - 1) : 0
      @source.each_with_index.map do |(label, value), i|
        Point.new(label: label, value: value, x: LEFT + step * i, y: BOTTOM - ([ 0, value ].max / c) * (BOTTOM - TOP))
      end
    end
  end
end
