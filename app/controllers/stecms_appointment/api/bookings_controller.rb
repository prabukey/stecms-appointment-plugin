module StecmsAppointment
	module Api
	  class BookingsController < ApiController

	  	def show
        booking = ::StecmsAppointment::Booking.find(params[:booking_id])
        BookingSerializer.new(booking)
	  	end

	  	def my
        bookings = current_user.bookings.active.includes(:salon).order("created_at desc")
        {name: current_user.full_name, total_booking: bookings.count, bookings: ActiveModel::SerializableResource.new(bookings, each_serializer: MyBookingSerializer)}
	  	end

      def month_calendar
        data = CalendarBooking.date_month_content(params[:month].to_i, params[:year].to_i)
        render json: data
      end

	  	def cancel
        booking = ::StecmsAppointment::Booking.find(params[:booking_id])
        booking.update(status: "user_cancelled")
        render json: { status: I18n.t('Prenotazione annullata') }
	  	end

	  	def create
	  		new_user = false
        begin
          parsed_time = params[:booking][:time_id].split(":")
          start_time = Time.new(params[:booking][:year_id], params[:booking][:month_id].to_i, params[:booking][:date_id].to_i, parsed_time[0], parsed_time[1]).to_i
          end_time = start_time + params[:booking][:length].to_i

          if params[:selected_card].present?
            booking_data = { 
              status: 'pending',
              tag: 'booking',
              note: ''
            }
          else
            booking_data = { 
              status: 'confirmed',
              tag: 'booking',
              note: ''
            }
          end

          params[:booking].except!("time_id", "month_id", "date_id", "year_id", "visitor_phone", "visitor_name", "visitor_email", "voucher_code")
          params[:booking][:start_time] = start_time
          params[:booking][:end_time] = end_time

          if ["custom_app_ios", "custom_app_android"].include? params[:booking][:from_where]
            if params[:booking][:from_where].eql?('custom_app_ios')
              params[:booking][:from_where] = "c_a_ios"
            else
              params[:booking][:from_where] = "c_a_andro"
            end
          end

          if params[:booking][:from_where].blank? or params[:booking][:from_where].to_s.length > 9
            params[:booking][:from_where] = "caapp"
          end

          params[:booking].merge!(booking_data)
          params[:booking][:stecms_appointment_service_id] = params[:booking][:s_treatment_id]
          params[:booking][:stecms_appointment_operator_id] = params[:booking][:operator_id]
          params[:booking].delete(:s_treatment_id)
          params[:booking].delete(:operator_id)

          booking = ::StecmsAppointment::Booking.new(booking_params)

          if params[:user_email].present?
            user = User.where(email: params[:user_email]).last
            if user
              customer = ::StecmsAppointment::Customer.where(email: user.email).last
              unless customer 
                customer = ::StecmsAppointment::Customer.create(email: params[:user_email], cell: params[:visitor_phone], name: params[:visitor_name])
              end
            end 
            booking.stecms_appointment_customer_id = customer.try(:id)
          else
            check_user = ::StecmsAppointment::Customer.where(email: params[:visitor_email]).first
            if check_user
              booking.stecms_appointment_customer_id = check_user.id
            else
              user = ::StecmsAppointment::Customer.new(email: params[:visitor_email], cell: params[:visitor_phone], name: params[:visitor_name])
              
              if user.save(validate: false)
                booking.stecms_appointment_customer_id = user.id
                new_user = true
              end
            end
          end
        rescue Exception => e 
          booking = Booking.new
        end
        
        composed_booking = booking.verify_composed_booking
        if booking.valid? and composed_booking[:status]
          booking.save
          
          if composed_booking[:composed]
            composed_booking[:result].each do |compose_booking_attr|
              compose_booking_attr.delete('ancestry')
              booking.children.create(compose_booking_attr)
            end
            booking.is_composed_treatment = true
            booking.save
          end

          @booking = booking
        else
          return {error: booking.errors.full_messages.join(", ")}
        end 

	  	end


      private 

      def booking_params
        params.require(:booking).permit(:from_where, :price, :discount_price, :start_time, :end_time, :stecms_appointment_service_id, :stecms_appointment_operator_id, :status, :tag, :note)
      end

	  end
	end
end