module Web
  module Superadmin
    # What the mailing's two forms say about a refused field, in the page's
    # language where it can.
    module MailForm
      private

      def mail_field_errors(record)
        record.errors.attribute_names.index_with do |attribute|
          if record.errors.of_kind?(attribute, :unknown_variable)
            helpers.ngt("superadmin.mailing.unknown_variable", names: record.unknown_variables.join(", "))
          elsif attribute == :recipients
            helpers.ngt("superadmin.mailing.none_selected")
          elsif record.errors.of_kind?(attribute, :blank)
            helpers.ngt("common.required")
          else
            I18n.with_locale(:en) { record.errors.full_messages_for(attribute).first }
          end
        end
      end
    end
  end
end
