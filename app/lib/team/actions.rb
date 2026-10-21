module Team
  # Back-office logins and a coach's own login, for /api/v1/staff,
  # /api/v1/coaches and the web UI's team page (moved unchanged from
  # Api::V1::StaffController and Api::V1::CoachesController).
  module Actions
    # A login only the admin may change.
    class Forbidden < StandardError; end

    # A new back-office login: the user and their place in this salle, in
    # one transaction; audited; then the address is sent its confirmation
    # link. A refused save raises RecordInvalid; a role that is not this
    # salle's raises RecordNotFound.
    def self.create_staff!(company:, by:, user_attributes:, staff_attributes:)
      user = User.new(user_attributes.merge(role: :staff, locale: user_attributes[:locale].presence || "fr"))
      staff_member = nil

      ActiveRecord::Base.transaction do
        user.save!
        staff_member = company.staff_members.create!(
          user: user,
          coach_id: staff_attributes[:coach_id],
          birthdate: staff_attributes[:birthdate],
          **role_assignment(company, staff_attributes)
        )
      end

      AuditLog.record!(
        company: company, user: by, action: "staff.created",
        auditable: staff_member, metadata: { role: staff_member.role_key, staff_email: user.email }
      )

      raw = user.generate_email_verification_token!
      AccountMailer.email_verification(user, raw).deliver_later
      staff_member
    end

    # Role, web access, birthdate. Returns whether it saved (the errors are
    # on the record); a change of role is audited.
    def self.update_staff(staff_member, company:, by:, staff_attributes:)
      previous_key = staff_member.role_key
      attrs = { active: staff_attributes[:active], birthdate: staff_attributes[:birthdate], coach_id: staff_attributes[:coach_id] }
                .compact.merge(role_assignment(company, staff_attributes))
      return false unless staff_member.update(attrs)

      if previous_key != staff_member.reload.role_key
        AuditLog.record!(
          company: company, user: by, action: "staff.role_changed",
          auditable: staff_member, metadata: { from: previous_key, to: staff_member.role_key }
        )
      end
      true
    end

    # Provisions (or resets) the coach's own login. Reached through the
    # :coaches capability, which moderators hold. It resets whatever login is
    # attached to the coach, so below the admin it only touches a login on
    # the coach role: an admin can link a coach to a moderator's or a
    # full-access login, and resetting that one would hand its access to
    # whoever did it.
    def self.set_coach_login!(coach, company:, by:, email:, password:)
      attached = coach.staff_member
      raise Forbidden, "Only the admin can change this login." if attached && !by.admin? && attached.role_key != "coach"

      coach.set_login!(email: email, password: password)
      AuditLog.record!(
        company: company, user: by, action: "coach.login_set",
        auditable: coach, metadata: { email: email }
      )
      coach
    end

    # Resolve an incoming assignment to the company's own Role row.
    #
    # `role_id` (the roles editor) is the real input. A bare `role` key
    # ("moderator", "coach") is still accepted because older clients
    # send it, and it means "the built-in role with that key, in this
    # company". Returns {} when neither is present, so an unrelated update
    # leaves the role alone.
    #
    # Both paths look the role up through the company, so a role id
    # belonging to another gym resolves to nothing rather than being
    # assigned.
    def self.role_assignment(company, staff_attributes)
      if staff_attributes[:role_id].present?
        { assigned_role: company.roles.find(staff_attributes[:role_id]) }
      elsif staff_attributes[:role].present?
        role = company.roles.find_by(key: staff_attributes[:role].to_s)
        raise ActiveRecord::RecordNotFound, "Unknown role" if role.nil?

        { assigned_role: role }
      else
        {}
      end
    end
    private_class_method :role_assignment
  end
end
