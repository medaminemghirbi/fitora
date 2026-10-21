# "Mes salles": every salle an admin runs, with what it holds, and every
# back-office login with where it works — for /api/v1/companies/network and
# the web UI's salles page (moved unchanged from Api::V1::CompaniesController).
# `current`: the salle the request works in, marked active.
module SalleNetwork
  def self.for(user, current)
    companies = user.companies.order(:created_at).to_a
    posts = user.salle_staff_members.where(coach_id: nil).includes(:user, :assigned_role).to_a
    members = user.salle_memberships.where(active: true).group(:company_id).count

    {
      companies: companies.map do |company|
        CompanySummarySerializer.new(company, active: company.id == current&.id).as_json.merge(
          city: company.city,
          members_count: members.fetch(company.id, 0),
          moderator_ids: posts.select { |p| p.company_id == company.id }.map(&:user_id)
        )
      end,
      moderators: posts.group_by(&:user_id).map do |_, records|
        first = records.min_by(&:created_at)
        user_record = first.user
        {
          id: user_record.id,
          full_name: user_record.full_name,
          email: EmailMask.call(user_record.email),
          role_name: first.assigned_role.name,
          role_key: first.assigned_role.key,
          active: records.any?(&:active?),
          company_ids: records.map(&:company_id)
        }
      end.sort_by { |m| m[:full_name].downcase }
    }
  end
end
