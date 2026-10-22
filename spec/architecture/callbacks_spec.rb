require "rails_helper"

# Rules that are only conventions rot. This one is tested.
#
# Rails keeps one callback per method name: a second
# `before_action :refuse_unless_admin, only: :b` silently replaces the first
# `before_action :refuse_unless_admin, only: :a`, and :a is open again. That
# took the admin's guard off five settings writes in the web UI (2026-10-22).
# A guard needed twice under different conditions is written once with every
# action, or the second one as a block.
#
# Reads the controller sources, so a new controller is covered the day it is
# written.
RSpec.describe "Controller callbacks", type: :model do
  CALLBACK = /^\s*((?:prepend_|append_)?(?:before|after|around)_action)\s+:([a-z_!?]+)/

  it "no controller declares the same callback twice" do
    offenders = Rails.root.glob("app/controllers/**/*.rb").flat_map { |path|
      path.read.scan(CALLBACK).tally.select { |_, count| count > 1 }.map { |(kind, name), count|
        "#{path.relative_path_from(Rails.root)} (#{kind} :#{name} ×#{count})"
      }
    }

    expect(offenders).to be_empty,
      "#{offenders.join(', ')}: the last declaration replaces the earlier ones. " \
      "List every action in one declaration instead."
  end
end
