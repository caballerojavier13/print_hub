require 'test_helper'

class PrintsControllerTest < ActionController::TestCase
  setup do
    @print = prints(:math_print)
    @printer = Cups.show_destinations.select {|p| p =~ /pdf/i}.first
    
    raise "Can't find a PDF printer to run tests with." unless @printer

    prepare_document_files
    prepare_settings
  end

  test 'should get operator index' do
    user = users(:operator)

    UserSession.create(user)
    get :index
    assert_response :success
    assert_not_nil assigns(:prints)
    assert_equal user.prints.count, assigns(:prints).size
    assert assigns(:prints).all? { |p| p.user_id == user.id }
    assert_select '#error_body', false
    assert_template 'prints/index'
  end

  test 'should get operator pending index' do
    user = users(:operator)

    UserSession.create(user)
    get :index, :pending => 'pending'
    assert_response :success
    assert_not_nil assigns(:prints)
    assert assigns(:prints).size > 0
    assert assigns(:prints).all?(&:pending_payment)
    assert_select '#error_body', false
    assert_template 'prints/index'
  end

  test 'should get admin index' do
    user = users(:administrator)
    
    UserSession.create(user)
    get :index
    assert_response :success
    assert_not_nil assigns(:prints)
    assert_equal Print.count, assigns(:prints).size
    assert assigns(:prints).any? { |p| p.user_id != user.id }
    assert_select '#error_body', false
    assert_template 'prints/index'
  end

  test 'should get admin pending index' do
    user = users(:administrator)

    UserSession.create(user)
    get :index, :pending => 'pending'
    assert_response :success
    assert_not_nil assigns(:prints)
    assert_equal Print.pending.count, assigns(:prints).size
    assert assigns(:prints).any? { |p| p.user_id != user.id }
    assert assigns(:prints).all?(&:pending_payment)
    assert_select '#error_body', false
    assert_template 'prints/index'
  end

  test 'should get new' do
    UserSession.create(users(:operator))
    get :new
    assert_response :success
    assert_not_nil assigns(:print)
    assert_select '#error_body', false
    assert_template 'prints/new'
  end

  test 'should create print' do
    UserSession.create(users(:operator))

    document = Document.find(documents(:math_book).id)
    counts_array = ['Print.count', 'PrintJob.count', 'Payment.count',
      'customer.prints.count']
    customer = Customer.find customers(:student).id

    assert_difference counts_array do
      post :create, :print => {
        :printer => @printer,
        :customer_id => customer.id,
        :print_jobs_attributes => {
          :new_1 => {
            :copies => '1',
            :pages => document.pages.to_s,
            # No importa el precio, se establece desde la configuración
            :price_per_copy => '12.0',
            :range => '',
            :two_sided => '0',
            :auto_document_name => 'Some name given in autocomplete',
            :document_id => document.id.to_s
          }
        }, :payments_attributes => {
          :new_1 => {
            :amount => '35.00',
            :paid => '35.00'
          }
        }
      }
    end

    assert_redirected_to print_path(assigns(:print))
    # Debe asignar el usuario autenticado como el creador de la impresión
    assert_equal users(:operator).id, assigns(:print).user.id
  end

  test 'should create print without documents in print jobs' do
    UserSession.create(users(:operator))

    counts_array = ['Print.count', 'PrintJob.count', 'Payment.count',
      'customer.prints.count']
    customer = Customer.find customers(:student).id

    assert_difference counts_array do
      post :create, :print => {
        :printer => @printer,
        :customer_id => customer.id,
        :print_jobs_attributes => {
          :new_1 => {
            :copies => '1',
            :pages => '30',
            # No importa el precio, se establece desde la configuración
            :price_per_copy => '12.0',
            :range => '',
            :two_sided => '0'
          }
        }, :payments_attributes => {
          :new_1 => {
            :amount => '3.00',
            :paid => '3.00'
          }
        }
      }
    end

    assert_redirected_to print_path(assigns(:print))
    # Debe asignar el usuario autenticado como el creador de la impresión
    assert_equal users(:operator).id, assigns(:print).user.id
  end

  test 'should create print with 3 decimal payment' do
    UserSession.create(users(:operator))

    counts_array = ['Print.count', 'PrintJob.count', 'Payment.count',
      'customer.prints.count']
    customer = Customer.find customers(:student).id
    Setting.price_per_one_sided_copy = '0.125'

    assert_difference counts_array do
      post :create, :print => {
        :printer => @printer,
        :customer_id => customer.id,
        :print_jobs_attributes => {
          :new_1 => {
            :copies => '1',
            :pages => '3',
            # No importa el precio, se establece desde la configuración
            :price_per_copy => '12.0',
            :range => '',
            :two_sided => '0'
          }
        }, :payments_attributes => {
          :new_1 => {
            :amount => '0.375',
            :paid => '0.375'
          }
        }
      }
    end

    assert_redirected_to print_path(assigns(:print))
    # Debe asignar el usuario autenticado como el creador de la impresión
    assert_equal users(:operator).id, assigns(:print).user.id
  end

  test 'should show print' do
    UserSession.create(users(:operator))
    get :show, :id => @print.to_param
    assert_response :success
    assert_not_nil assigns(:print)
    assert_select '#error_body', false
    assert_template 'prints/show'
  end

  test 'should get edit' do
    UserSession.create(users(:operator))
    get :edit, :id => @print.to_param
    assert_response :success
    assert_not_nil assigns(:print)
    assert_select '#error_body', false
    assert_template 'prints/edit'
  end

  test 'should not get edit' do
    UserSession.create(users(:administrator))

    print = Print.where(:pending_payment => false).first

    # Se debe producir un error al tratar de editar una impresión no pendiente
    get :edit, :id => print.to_param
    assert_response :success
    assert_nil assigns(:print)
    assert_select '#error_body'
    assert_template 'shared/show_error'
  end

  test 'should update print' do
    user = User.find users(:operator).id
    customer = Customer.find customers(:teacher).id
    math_notes = Document.find(documents(:math_notes).id)
    math_book = Document.find(documents(:math_book).id)
    immutable_counts = ['user.prints.count', 'Payment.count',
      'customer.prints.count']

    UserSession.create(user)

    assert_not_equal customer.id, @print.customer_id

    assert_no_difference immutable_counts do
      assert_difference ['@print.print_jobs.count'] do
        put :update, :id => @print.to_param, :print => {
          :printer => @printer,
          :customer_id => customer.id,
          :user_id => users(:administrator).id,
          :print_jobs_attributes => {
            print_jobs(:math_job_1).id => {
              :id => print_jobs(:math_job_1).id,
              :auto_document_name => 'Some name given in autocomplete',
              :document_id => math_notes.id.to_s,
              :copies => '123',
              :pages => math_notes.pages.to_s,
              # No importa el precio, se establece desde la configuración
              :price_per_copy => '12.0',
              :range => '',
              :two_sided => '0'
            },
            print_jobs(:math_job_2).id => {
              :id => print_jobs(:math_job_2).id,
              :auto_document_name => 'Some name given in autocomplete',
              :document_id => math_book.id.to_s,
              :copies => '234',
              :pages => math_book.pages.to_s,
              # No importa el precio, se establece desde la configuración
              :price_per_copy => '0.2',
              :range => '',
              :two_sided => '0'
            },
            :new_1 => {
              :auto_document_name => 'Some name given in autocomplete',
              :document_id => math_book.id.to_s,
              :copies => '1',
              # Sin páginas intencionalmente
              # No importa el precio, se establece desde la configuración
              :price_per_copy => '0.3',
              :range => '',
              :two_sided => '0'
            }
          },
          :payments_attributes => {
            payments(:math_payment).id => {
              :id => payments(:math_payment).id.to_s,
              :amount => '8372.6',
              :paid => '7.50'
            }
          }
        }
      end
    end

    assert_redirected_to print_path(@print)
    # No se puede cambiar el usuario que creo una impresión
    assert_not_equal users(:administrator).id, @print.reload.user_id
    # No se puede cambiar el cliente de la impresión
    assert_not_equal customer.id, @print.reload.customer_id
    assert_equal 123, @print.print_jobs.find_by_document_id(
      documents(:math_notes).id).copies
    assert_equal math_book.pages, @print.print_jobs.order('id ASC').last.pages
  end

  test 'should get autocomplete document list' do
    Document.all.each do |d|
      d.update_attributes!(:tag_path => d.tags.map(&:to_s).join(' ## '))
    end

    UserSession.create(users(:operator))
    get :autocomplete_for_document_name, :q => 'Math'
    assert_response :success
    assert_select 'li[data-id]', 2

    # TODO: revisar por que estos test no funcionan
    get :autocomplete_for_document_name, :q => 'note'
    assert_response :success
    assert_select 'li[data-id]', 2

    get :autocomplete_for_document_name, :q => '001'
    assert_response :success
    assert_select 'li[data-id]', 1

    get :autocomplete_for_document_name, :q => 'physics'
    assert_response :success
    assert_select 'li[data-id]', 1

    get :autocomplete_for_document_name, :q => 'phyxyz'
    assert_response :success
    assert_select 'li[data-id]', false
  end

  test 'should get autocomplete customer list' do
    UserSession.create(users(:operator))
    get :autocomplete_for_customer_name, :q => 'wa'
    assert_response :success
    assert_select 'li[data-id]', 2

    get :autocomplete_for_customer_name, :q => 'kin'
    assert_response :success
    assert_select 'li[data-id]', 1

    get :autocomplete_for_customer_name, :q => 'phyxyz'
    assert_response :success
    assert_select 'li[data-id]', false
  end
end