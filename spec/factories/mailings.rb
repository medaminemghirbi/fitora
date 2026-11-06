FactoryBot.define do
  factory :mail_template do
    sequence(:name) { |n| "Modèle #{n}" }
    subject { "Bonjour {{prenom}}" }
    body { "Un mot pour {{salle}}." }
  end

  factory :mailing do
    association :sent_by, factory: [ :user, :superadmin ]
    subject { "Bonjour {{prenom}}" }
    body { "Un mot pour {{salle}}." }
  end

  factory :mailing_recipient do
    mailing
    association :user, factory: [ :user, :admin ]
    email { user.email }
  end
end
