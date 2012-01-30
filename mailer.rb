require 'sinatra'
require 'stripe'
require 'json'
require 'pony'

Stripe::api_key = ENV['STRIPE_SECRET_KEY']

post '/stripe-webhook-url' do
  data = JSON.parse request.body.read, :symbolize_names => true
  p data

  puts "Received event with ID: #{data[:id]} Type: #{data[:type]}"

  # Retrieving the event from the Stripe API guarantees its authenticity  
  event = Stripe::Event.retrieve(data[:id])

  # This will send receipts on succesful invoices
  # You could also send emails on all charge.succeeded events
  if event.type == 'invoice.payment_succeeded'
    email_invoice_receipt(event.data.object)
  end
end

def email_invoice_receipt(invoice)
  puts "Emailing customer for invoice: #{invoice.id} amount: #{format_stripe_amount(invoice.total)}"

  customer = Stripe::Customer.retrieve(invoice.customer)

  # Make sure to customize your from address
  from_address = "MyApp Support <support@myapp.com>"
  subject = "Your payment has been received"

  Pony.mail(
    :from => from_address,
    :to => customer.email,
    :subject => subject,
    :body => payment_received_body(invoice, customer),
    :via => :smtp,
    :via_options => default_email_options)

  puts "Email sent to #{customer.email}"
end

def format_stripe_amount(amount)
  sprintf('$%0.2f', amount.to_f / 100.0).gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
end

def format_stripe_timestamp(timestamp)
  Time.at(timestamp).strftime("%m/%d/%Y")
end

def payment_received_body(invoice, customer)
  subscription = invoice.lines.subscriptions[0]
  <<EOF
Dear #{customer.email}:

This is a receipt for your subscription. This is only a receipt, 
no payment is due. Thanks for your continued support!

-------------------------------------------------
SUBSCRIPTION RECEIPT - #{Time.now.strftime("%m/%d/%Y")}

Email: #{customer.email}
Plan: #{subscription.plan.name}
Amount: #{format_stripe_amount(invoice.total)} (USD)

For service between #{format_stripe_timestamp(subscription.period.start)} and #{format_stripe_timestamp(subscription.period.end)}

-------------------------------------------------

EOF
end

# You can customize this for whatever email provider you want to use,
# like Mailgun, SendGrid, or even Gmail. These settings are for Mailgun
def default_email_options
  { 
    :address              => ENV['MAILGUN_SMTP_SERVER'],
    :port                 => ENV['MAILGUN_SMTP_PORT'],
    :enable_starttls_auto => true,
    :user_name            => ENV['MAILGUN_SMTP_LOGIN'],
    :password             => ENV['MAILGUN_SMTP_PASSWORD'],
    :authentication       => :plain,
  }
end
